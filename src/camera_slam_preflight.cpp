#include <chrono>
#include <cstdint>
#include <exception>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/camera_info.hpp"
#include "sensor_msgs/msg/image.hpp"
#include "yoga_cam_sub/stream_diagnostics.hpp"

using namespace std::chrono_literals;

class CameraSlamPreflight : public rclcpp::Node
{
public:
  CameraSlamPreflight()
  : Node("camera_slam_preflight")
  {
    load_parameters();
    validate_parameters();

    const auto qos = rclcpp::SensorDataQoS();
    image_sub_ = this->create_subscription<sensor_msgs::msg::Image>(
      image_topic_,
      qos,
      std::bind(&CameraSlamPreflight::on_image, this, std::placeholders::_1));
    camera_info_sub_ = this->create_subscription<sensor_msgs::msg::CameraInfo>(
      camera_info_topic_,
      qos,
      std::bind(&CameraSlamPreflight::on_camera_info, this, std::placeholders::_1));
    watchdog_timer_ = this->create_wall_timer(1s, std::bind(&CameraSlamPreflight::check_timeout, this));

    start_time_ = this->now();
    RCLCPP_INFO(
      this->get_logger(),
      "Узел camera_slam_preflight запущен. image_topic=%s camera_info_topic=%s required_frames=%d min_fps=%.2f max_runtime_seconds=%d expected_frame_id=%s.",
      image_topic_.c_str(),
      camera_info_topic_.c_str(),
      required_frames_,
      min_fps_,
      max_runtime_seconds_,
      expected_frame_id_.empty() ? "<не задан>" : expected_frame_id_.c_str());
  }

  int exit_code() const
  {
    return exit_code_;
  }

private:
  void load_parameters()
  {
    image_topic_ = this->declare_parameter<std::string>("image_topic", "/camera/image_raw");
    camera_info_topic_ = this->declare_parameter<std::string>("camera_info_topic", "/camera/camera_info");
    expected_frame_id_ =
      this->declare_parameter<std::string>("expected_frame_id", "camera_optical_frame");
    required_frames_ = static_cast<int>(this->declare_parameter<std::int64_t>("required_frames", 30));
    max_runtime_seconds_ =
      static_cast<int>(this->declare_parameter<std::int64_t>("max_runtime_seconds", 20));
    log_every_n_frames_ =
      static_cast<int>(this->declare_parameter<std::int64_t>("log_every_n_frames", 10));
    min_fps_ = this->declare_parameter<double>("min_fps", 5.0);
  }

  void validate_parameters() const
  {
    if (image_topic_.empty()) {
      throw std::invalid_argument("Параметр image_topic не должен быть пустым.");
    }
    if (camera_info_topic_.empty()) {
      throw std::invalid_argument("Параметр camera_info_topic не должен быть пустым.");
    }
    if (required_frames_ <= 0) {
      throw std::invalid_argument("Параметр required_frames должен быть положительным.");
    }
    if (max_runtime_seconds_ <= 0) {
      throw std::invalid_argument("Параметр max_runtime_seconds должен быть положительным.");
    }
    if (log_every_n_frames_ <= 0) {
      throw std::invalid_argument("Параметр log_every_n_frames должен быть положительным.");
    }
    if (min_fps_ <= 0.0) {
      throw std::invalid_argument("Параметр min_fps должен быть больше нуля.");
    }
  }

  void on_camera_info(const sensor_msgs::msg::CameraInfo::SharedPtr message)
  {
    latest_camera_info_ = *message;
    has_camera_info_ = true;
    ++camera_info_count_;

    if (camera_info_count_ == 1U) {
      const bool template_like = yoga_cam_sub::camera_info_matches_template(*message);
      RCLCPP_INFO(
        this->get_logger(),
        "Получен первый CameraInfo: width=%u height=%u frame_id=%s distortion_model=%s template_like=%s.",
        message->width,
        message->height,
        message->header.frame_id.c_str(),
        message->distortion_model.c_str(),
        template_like ? "true" : "false");
      if (template_like) {
        RCLCPP_WARN(
          this->get_logger(),
          "CameraInfo совпадает с шаблонной калибровкой. Для реального SLAM лучше использовать откалиброванный YAML.");
      }
    }
  }

  void on_image(const sensor_msgs::msg::Image::SharedPtr message)
  {
    ++image_count_;
    image_timestamps_ns_.push_back(resolve_timestamp_ns(*message));
    last_encoding_ = message->encoding;
    last_frame_id_ = message->header.frame_id;

    if (!expected_frame_id_.empty() && message->header.frame_id != expected_frame_id_) {
      register_error(
        "Image frame_id не совпадает с expected_frame_id: expected='" + expected_frame_id_ +
        "' actual='" + message->header.frame_id + "'.");
    }

    if (has_camera_info_) {
      for (const auto & error : yoga_cam_sub::validate_image_and_camera_info(*message, latest_camera_info_)) {
        register_error(error);
      }
    } else {
      RCLCPP_WARN_THROTTLE(
        this->get_logger(),
        *this->get_clock(),
        3000,
        "Изображения уже приходят, но CameraInfo ещё не получен.");
    }

    if (image_count_ <= 3U || image_count_ % static_cast<std::size_t>(log_every_n_frames_) == 0U) {
      RCLCPP_INFO(
        this->get_logger(),
        "Preflight получил кадр #%zu: frame_id=%s width=%u height=%u encoding=%s camera_info_count=%zu.",
        image_count_,
        message->header.frame_id.c_str(),
        message->width,
        message->height,
        message->encoding.c_str(),
        camera_info_count_);
    }

    if (has_camera_info_ && image_count_ >= static_cast<std::size_t>(required_frames_)) {
      finalize_success_or_failure();
    }
  }

  std::int64_t resolve_timestamp_ns(const sensor_msgs::msg::Image & message) const
  {
    const std::int64_t stamp_ns =
      static_cast<std::int64_t>(message.header.stamp.sec) * 1'000'000'000LL +
      static_cast<std::int64_t>(message.header.stamp.nanosec);

    // Если upstream не проставил stamp, используем время получения, чтобы всё равно оценить поток.
    return stamp_ns > 0 ? stamp_ns : this->now().nanoseconds();
  }

  void register_error(const std::string & error)
  {
    const auto [_, inserted] = validation_errors_.insert(error);
    if (inserted) {
      RCLCPP_ERROR(this->get_logger(), "SLAM preflight обнаружил проблему: %s", error.c_str());
    }
  }

  void finalize_success_or_failure()
  {
    if (finished_) {
      return;
    }
    finished_ = true;

    try {
      const auto timing_statistics = yoga_cam_sub::calculate_timing_statistics(image_timestamps_ns_);
      RCLCPP_INFO(
        this->get_logger(),
        "Preflight summary: images=%zu camera_infos=%zu average_fps=%.2f mean_period_ms=%.2f min_period_ms=%.2f max_period_ms=%.2f stddev_period_ms=%.2f frame_id=%s encoding=%s.",
        image_count_,
        camera_info_count_,
        timing_statistics.average_fps,
        timing_statistics.mean_period_ms,
        timing_statistics.min_period_ms,
        timing_statistics.max_period_ms,
        timing_statistics.stddev_period_ms,
        last_frame_id_.c_str(),
        last_encoding_.c_str());

      if (timing_statistics.average_fps < min_fps_) {
        register_error(
          "Средний FPS ниже допустимого порога: observed=" + to_string_with_precision(timing_statistics.average_fps) +
          " min=" + to_string_with_precision(min_fps_) + ".");
      }
    } catch (const std::exception & error) {
      register_error(std::string("Не удалось рассчитать статистику потока: ") + error.what());
    }

    if (!validation_errors_.empty()) {
      exit_code_ = 1;
      RCLCPP_FATAL(
        this->get_logger(),
        "SLAM preflight завершён с ошибками. Найдено проблем: %zu.",
        validation_errors_.size());
    } else {
      exit_code_ = 0;
      RCLCPP_INFO(this->get_logger(), "SLAM preflight завершён успешно. Поток готов к следующему этапу интеграции.");
    }

    rclcpp::shutdown();
  }

  void check_timeout()
  {
    if (finished_) {
      return;
    }

    const auto elapsed_seconds = (this->now() - start_time_).seconds();
    if (elapsed_seconds < static_cast<double>(max_runtime_seconds_)) {
      return;
    }

    if (!has_camera_info_) {
      register_error("За время ожидания не был получен ни один CameraInfo.");
    }
    if (image_count_ < static_cast<std::size_t>(required_frames_)) {
      register_error(
        "Не набрано требуемое число кадров: received=" + std::to_string(image_count_) +
        " required=" + std::to_string(required_frames_) + ".");
    }

    finalize_success_or_failure();
  }

  std::string to_string_with_precision(double value) const
  {
    std::ostringstream stream;
    stream.setf(std::ios::fixed);
    stream.precision(2);
    stream << value;
    return stream.str();
  }

  std::string image_topic_;
  std::string camera_info_topic_;
  std::string expected_frame_id_;
  int required_frames_{30};
  int max_runtime_seconds_{20};
  int log_every_n_frames_{10};
  double min_fps_{5.0};
  int exit_code_{1};
  bool finished_{false};
  bool has_camera_info_{false};
  std::size_t image_count_{0};
  std::size_t camera_info_count_{0};
  std::vector<std::int64_t> image_timestamps_ns_;
  std::set<std::string> validation_errors_;
  std::string last_encoding_;
  std::string last_frame_id_;
  rclcpp::Time start_time_;
  sensor_msgs::msg::CameraInfo latest_camera_info_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr image_sub_;
  rclcpp::Subscription<sensor_msgs::msg::CameraInfo>::SharedPtr camera_info_sub_;
  rclcpp::TimerBase::SharedPtr watchdog_timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);

  int exit_code = 1;
  try {
    auto node = std::make_shared<CameraSlamPreflight>();
    rclcpp::spin(node);
    exit_code = node->exit_code();
  } catch (const std::exception & error) {
    RCLCPP_FATAL(
      rclcpp::get_logger("camera_slam_preflight"),
      "Узел camera_slam_preflight завершился с ошибкой: %s",
      error.what());
  }

  rclcpp::shutdown();
  return exit_code;
}
