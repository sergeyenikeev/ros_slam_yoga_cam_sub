#include <chrono>
#include <cstdint>
#include <exception>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <vector>

#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/image.hpp"
#include "yoga_cam_sub/feature_diagnostics.hpp"

using namespace std::chrono_literals;

class CameraFeatureMonitor : public rclcpp::Node
{
public:
  CameraFeatureMonitor()
  : Node("camera_feature_monitor")
  {
    load_parameters();
    validate_parameters();

    const auto qos = rclcpp::SensorDataQoS();
    image_sub_ = this->create_subscription<sensor_msgs::msg::Image>(
      image_topic_,
      qos,
      std::bind(&CameraFeatureMonitor::on_image, this, std::placeholders::_1));
    watchdog_timer_ = this->create_wall_timer(1s, std::bind(&CameraFeatureMonitor::check_timeout, this));

    start_time_ = this->now();
    RCLCPP_INFO(
      this->get_logger(),
      "Узел camera_feature_monitor запущен. image_topic=%s required_frames=%d max_runtime_seconds=%d min_average_keypoints=%d min_average_grid_coverage_ratio=%.2f min_average_blur_score=%.2f min_average_brightness_mean=%.2f.",
      image_topic_.c_str(),
      required_frames_,
      max_runtime_seconds_,
      thresholds_.min_average_keypoints,
      thresholds_.min_average_grid_coverage_ratio,
      thresholds_.min_average_blur_score,
      thresholds_.min_average_brightness_mean);
  }

  int exit_code() const
  {
    return exit_code_;
  }

private:
  void load_parameters()
  {
    image_topic_ = this->declare_parameter<std::string>("image_topic", "/camera/image_raw");
    required_frames_ = static_cast<int>(this->declare_parameter<std::int64_t>("required_frames", 20));
    max_runtime_seconds_ =
      static_cast<int>(this->declare_parameter<std::int64_t>("max_runtime_seconds", 20));
    log_every_n_frames_ =
      static_cast<int>(this->declare_parameter<std::int64_t>("log_every_n_frames", 10));
    max_features_ = static_cast<int>(this->declare_parameter<std::int64_t>("max_features", 500));
    grid_rows_ = static_cast<int>(this->declare_parameter<std::int64_t>("grid_rows", 4));
    grid_cols_ = static_cast<int>(this->declare_parameter<std::int64_t>("grid_cols", 4));

    thresholds_.min_average_keypoints =
      static_cast<int>(this->declare_parameter<std::int64_t>("min_average_keypoints", 150));
    thresholds_.min_average_grid_coverage_ratio =
      this->declare_parameter<double>("min_average_grid_coverage_ratio", 0.35);
    thresholds_.min_average_blur_score =
      this->declare_parameter<double>("min_average_blur_score", 80.0);
    thresholds_.min_average_brightness_mean =
      this->declare_parameter<double>("min_average_brightness_mean", 25.0);
  }

  void validate_parameters() const
  {
    if (image_topic_.empty()) {
      throw std::invalid_argument("Параметр image_topic не должен быть пустым.");
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
    if (max_features_ <= 0) {
      throw std::invalid_argument("Параметр max_features должен быть положительным.");
    }
    if (grid_rows_ <= 0 || grid_cols_ <= 0) {
      throw std::invalid_argument("Параметры grid_rows и grid_cols должны быть положительными.");
    }

    // Валидируем пороги через ту же библиотечную функцию, которую используем в runtime-отчёте.
    yoga_cam_sub::FeatureMonitorSummary dry_run_summary;
    dry_run_summary.frames = 1U;
    dry_run_summary.average_keypoints = static_cast<double>(thresholds_.min_average_keypoints);
    dry_run_summary.average_grid_coverage_ratio = thresholds_.min_average_grid_coverage_ratio;
    dry_run_summary.average_blur_score = thresholds_.min_average_blur_score;
    dry_run_summary.average_brightness_mean = thresholds_.min_average_brightness_mean;
    static_cast<void>(yoga_cam_sub::validate_feature_summary(dry_run_summary, thresholds_));
  }

  void on_image(const sensor_msgs::msg::Image::SharedPtr message)
  {
    if (finished_) {
      return;
    }

    try {
      const cv::Mat frame_bgr = yoga_cam_sub::convert_image_message_to_bgr(*message);
      const auto metrics = yoga_cam_sub::analyze_feature_frame(
        frame_bgr,
        max_features_,
        grid_rows_,
        grid_cols_);

      frame_metrics_.push_back(metrics);
      ++image_count_;
      last_encoding_ = message->encoding;
      last_frame_id_ = message->header.frame_id;

      if (image_count_ <= 3U || image_count_ % static_cast<std::size_t>(log_every_n_frames_) == 0U) {
        RCLCPP_INFO(
          this->get_logger(),
          "Feature monitor получил кадр #%zu: frame_id=%s encoding=%s keypoints=%zu grid_coverage=%.2f blur_score=%.2f brightness_mean=%.2f.",
          image_count_,
          message->header.frame_id.c_str(),
          message->encoding.c_str(),
          metrics.keypoints,
          metrics.grid_coverage_ratio,
          metrics.blur_score,
          metrics.brightness_mean);
      }

      if (image_count_ >= static_cast<std::size_t>(required_frames_)) {
        finalize_success_or_failure();
      }
    } catch (const std::exception & error) {
      register_error(std::string("Не удалось обработать входной кадр: ") + error.what());
      finalize_success_or_failure();
    }
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

    if (image_count_ < static_cast<std::size_t>(required_frames_)) {
      register_error(
        "Не набрано требуемое число кадров для feature-мониторинга: received=" +
        std::to_string(image_count_) +
        " required=" + std::to_string(required_frames_) + ".");
    }

    finalize_success_or_failure();
  }

  void register_error(const std::string & error)
  {
    const auto [_, inserted] = validation_errors_.insert(error);
    if (inserted) {
      RCLCPP_ERROR(this->get_logger(), "Feature monitor обнаружил проблему: %s", error.c_str());
    }
  }

  void finalize_success_or_failure()
  {
    if (finished_) {
      return;
    }
    finished_ = true;

    if (frame_metrics_.empty()) {
      register_error("Feature monitor не получил ни одного кадра для анализа.");
    } else {
      try {
        const auto summary = yoga_cam_sub::summarize_feature_metrics(frame_metrics_);
        RCLCPP_INFO(
          this->get_logger(),
          "Feature summary: images=%zu average_keypoints=%.2f min_keypoints=%zu average_response=%.4f average_coverage=%.2f average_blur=%.2f average_brightness=%.2f average_contrast=%.2f frame_id=%s encoding=%s.",
          summary.frames,
          summary.average_keypoints,
          summary.min_keypoints,
          summary.average_keypoint_response,
          summary.average_grid_coverage_ratio,
          summary.average_blur_score,
          summary.average_brightness_mean,
          summary.average_brightness_stddev,
          last_frame_id_.c_str(),
          last_encoding_.c_str());

        for (const auto & error : yoga_cam_sub::validate_feature_summary(summary, thresholds_)) {
          register_error(error);
        }
      } catch (const std::exception & error) {
        register_error(std::string("Не удалось собрать feature summary: ") + error.what());
      }
    }

    if (!validation_errors_.empty()) {
      exit_code_ = 1;
      RCLCPP_FATAL(
        this->get_logger(),
        "Feature monitor завершён с ошибками. Найдено проблем: %zu.",
        validation_errors_.size());
    } else {
      exit_code_ = 0;
      RCLCPP_INFO(
        this->get_logger(),
        "Feature monitor завершён успешно. Поток содержит достаточно визуальных ориентиров для следующего шага SLAM.");
    }

    rclcpp::shutdown();
  }

  std::string image_topic_;
  int required_frames_{20};
  int max_runtime_seconds_{20};
  int log_every_n_frames_{10};
  int max_features_{500};
  int grid_rows_{4};
  int grid_cols_{4};
  int exit_code_{1};
  bool finished_{false};
  std::size_t image_count_{0};
  std::string last_encoding_;
  std::string last_frame_id_;
  rclcpp::Time start_time_;
  yoga_cam_sub::FeatureMonitorThresholds thresholds_;
  std::vector<yoga_cam_sub::FeatureFrameMetrics> frame_metrics_;
  std::set<std::string> validation_errors_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr image_sub_;
  rclcpp::TimerBase::SharedPtr watchdog_timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);

  int exit_code = 1;
  try {
    auto node = std::make_shared<CameraFeatureMonitor>();
    rclcpp::spin(node);
    exit_code = node->exit_code();
  } catch (const std::exception & error) {
    RCLCPP_FATAL(
      rclcpp::get_logger("camera_feature_monitor"),
      "Узел camera_feature_monitor завершился с ошибкой: %s",
      error.what());
  }

  rclcpp::shutdown();
  return exit_code;
}
