#include <chrono>
#include <cstdint>
#include <exception>
#include <functional>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <opencv2/core/mat.hpp>
#include <opencv2/videoio.hpp>

#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/camera_info.hpp"
#include "sensor_msgs/msg/image.hpp"
#include "yoga_cam_sub/camera_utils.hpp"

using namespace std::chrono_literals;

class CameraPublisher : public rclcpp::Node
{
public:
  CameraPublisher()
  : Node("camera_publisher"), published_frames_(0), failed_reads_(0), active_backend_(cv::CAP_ANY)
  {
    load_parameters();
    validate_parameters();

    const auto qos = rclcpp::SensorDataQoS();
    image_pub_ = this->create_publisher<sensor_msgs::msg::Image>(camera_parameters_.image_topic, qos);
    camera_info_pub_ =
      this->create_publisher<sensor_msgs::msg::CameraInfo>(camera_parameters_.camera_info_topic, qos);

    open_camera();

    const auto period = std::chrono::duration<double>(1.0 / camera_parameters_.fps);
    timer_ = this->create_wall_timer(
      std::chrono::duration_cast<std::chrono::milliseconds>(period),
      std::bind(&CameraPublisher::publish_frame, this));

    RCLCPP_INFO(
      this->get_logger(),
      "Узел camera_publisher запущен. device_index=%d width=%d height=%d fps=%.2f frame_id=%s image_topic=%s camera_info_topic=%s use_msmf=%s max_frames=%d.",
      camera_parameters_.device_index,
      camera_parameters_.width,
      camera_parameters_.height,
      camera_parameters_.fps,
      camera_parameters_.frame_id.c_str(),
      camera_parameters_.image_topic.c_str(),
      camera_parameters_.camera_info_topic.c_str(),
      camera_parameters_.use_msmf ? "true" : "false",
      camera_parameters_.max_frames);
  }

  ~CameraPublisher() override
  {
    if (cap_.isOpened()) {
      cap_.release();
      RCLCPP_INFO(this->get_logger(), "Камера освобождена.");
    }
  }

private:
  void load_parameters()
  {
    camera_parameters_.device_index = static_cast<int>(this->declare_parameter<std::int64_t>("device_index", 0));
    camera_parameters_.width = static_cast<int>(this->declare_parameter<std::int64_t>("width", 640));
    camera_parameters_.height = static_cast<int>(this->declare_parameter<std::int64_t>("height", 360));
    camera_parameters_.fps = this->declare_parameter<double>("fps", 30.0);
    camera_parameters_.frame_id =
      this->declare_parameter<std::string>("frame_id", "camera_optical_frame");
    camera_parameters_.image_topic =
      this->declare_parameter<std::string>("image_topic", "/camera/image_raw");
    camera_parameters_.camera_info_topic =
      this->declare_parameter<std::string>("camera_info_topic", "/camera/camera_info");
    camera_parameters_.use_msmf = this->declare_parameter<bool>("use_msmf", true);
    camera_parameters_.max_frames = static_cast<int>(this->declare_parameter<std::int64_t>("max_frames", 0));

    distortion_model_ = this->declare_parameter<std::string>("distortion_model", "plumb_bob");
    distortion_coefficients_ =
      this->declare_parameter<std::vector<double>>("distortion_coefficients", std::vector<double>{});
    camera_matrix_ =
      this->declare_parameter<std::vector<double>>("camera_matrix", std::vector<double>{});
    rectification_matrix_ =
      this->declare_parameter<std::vector<double>>("rectification_matrix", std::vector<double>{});
    projection_matrix_ =
      this->declare_parameter<std::vector<double>>("projection_matrix", std::vector<double>{});

    RCLCPP_INFO(
      this->get_logger(),
      "Загружены параметры камеры. distortion_model=%s, коэффициентов дисторсии=%zu, camera_matrix=%zu, rectification_matrix=%zu, projection_matrix=%zu.",
      distortion_model_.c_str(),
      distortion_coefficients_.size(),
      camera_matrix_.size(),
      rectification_matrix_.size(),
      projection_matrix_.size());
  }

  void validate_parameters()
  {
    const auto errors = yoga_cam_sub::validate_camera_parameters(camera_parameters_);
    if (errors.empty()) {
      return;
    }

    std::ostringstream stream;
    stream << "Некорректная конфигурация camera_publisher:";
    for (const auto & error : errors) {
      stream << ' ' << error;
    }

    throw std::invalid_argument(stream.str());
  }

  void open_camera()
  {
    // Для Windows-ноутбуков сначала пробуем MSMF, затем универсальный fallback OpenCV.
    std::vector<int> backends;
    if (camera_parameters_.use_msmf) {
      backends = {cv::CAP_MSMF, cv::CAP_ANY};
    } else {
      backends = {cv::CAP_ANY, cv::CAP_MSMF};
    }

    for (const int backend : backends) {
      if (try_open_camera(backend)) {
        active_backend_ = backend;
        return;
      }
    }

    std::ostringstream stream;
    stream << "Не удалось открыть камеру с индексом " << camera_parameters_.device_index
           << " ни через один backend OpenCV.";
    throw std::runtime_error(stream.str());
  }

  bool try_open_camera(int backend)
  {
    if (cap_.isOpened()) {
      cap_.release();
    }

    RCLCPP_INFO(
      this->get_logger(),
      "Пробуем открыть камеру: device_index=%d backend=%s.",
      camera_parameters_.device_index,
      yoga_cam_sub::describe_video_backend(backend).c_str());

    if (!cap_.open(camera_parameters_.device_index, backend)) {
      RCLCPP_WARN(
        this->get_logger(),
        "OpenCV не смог открыть камеру через backend=%s.",
        yoga_cam_sub::describe_video_backend(backend).c_str());
      return false;
    }

    cap_.set(cv::CAP_PROP_FRAME_WIDTH, camera_parameters_.width);
    cap_.set(cv::CAP_PROP_FRAME_HEIGHT, camera_parameters_.height);
    cap_.set(cv::CAP_PROP_FPS, camera_parameters_.fps);

    const int actual_width = static_cast<int>(cap_.get(cv::CAP_PROP_FRAME_WIDTH));
    const int actual_height = static_cast<int>(cap_.get(cv::CAP_PROP_FRAME_HEIGHT));
    const double actual_fps = cap_.get(cv::CAP_PROP_FPS);

    RCLCPP_INFO(
      this->get_logger(),
      "Камера открыта: backend=%s actual_width=%d actual_height=%d actual_fps=%.2f.",
      yoga_cam_sub::describe_video_backend(backend).c_str(),
      actual_width,
      actual_height,
      actual_fps);
    return true;
  }

  void refresh_calibration_if_needed(const cv::Size & image_size)
  {
    if (image_size == current_frame_size_) {
      return;
    }

    // CameraInfo пересобирается только при изменении фактического размера кадра.
    calibration_ = yoga_cam_sub::merge_calibration_overrides(
      image_size,
      distortion_model_,
      distortion_coefficients_,
      camera_matrix_,
      rectification_matrix_,
      projection_matrix_);
    current_frame_size_ = image_size;

    RCLCPP_INFO(
      this->get_logger(),
      "Подготовлен CameraInfo для размера %dx%d. Значения калибровки %s.",
      image_size.width,
      image_size.height,
      camera_matrix_.empty() ? "взяты из шаблона по умолчанию" : "загружены из параметров");
  }

  void publish_frame()
  {
    cv::Mat raw_frame;
    if (!cap_.read(raw_frame) || raw_frame.empty()) {
      ++failed_reads_;
      RCLCPP_WARN_THROTTLE(
        this->get_logger(),
        *this->get_clock(),
        3000,
        "Не удалось прочитать кадр с камеры. Количество последовательных ошибок: %zu.",
        failed_reads_);
      return;
    }

    try {
      cv::Mat frame = yoga_cam_sub::prepare_frame_for_publish(raw_frame);
      refresh_calibration_if_needed(frame.size());

      const auto stamp = this->now();
      auto image_message = yoga_cam_sub::build_image_message(
        frame,
        camera_parameters_.frame_id,
        stamp);
      auto camera_info_message = yoga_cam_sub::build_camera_info_message(
        frame.size(),
        camera_parameters_.frame_id,
        stamp,
        calibration_);

      image_pub_->publish(image_message);
      camera_info_pub_->publish(camera_info_message);

      ++published_frames_;
      failed_reads_ = 0;

      if (published_frames_ <= 5 || published_frames_ % 150 == 0) {
        RCLCPP_INFO(
          this->get_logger(),
          "Опубликован кадр #%zu: width=%u height=%u encoding=%s backend=%s.",
          published_frames_,
          image_message.width,
          image_message.height,
          image_message.encoding.c_str(),
          yoga_cam_sub::describe_video_backend(active_backend_).c_str());
        RCLCPP_INFO(
          this->get_logger(),
          "Опубликован CameraInfo #%zu: width=%u height=%u distortion_model=%s.",
          published_frames_,
          camera_info_message.width,
          camera_info_message.height,
          camera_info_message.distortion_model.c_str());
      }

      if (camera_parameters_.max_frames > 0 &&
        static_cast<int>(published_frames_) >= camera_parameters_.max_frames)
      {
        RCLCPP_INFO(
          this->get_logger(),
          "Достигнут лимит max_frames=%d. Узел завершает публикацию.",
          camera_parameters_.max_frames);
        rclcpp::shutdown();
      }
    } catch (const std::exception & error) {
      RCLCPP_ERROR_THROTTLE(
        this->get_logger(),
        *this->get_clock(),
        3000,
        "Ошибка подготовки кадра к публикации: %s",
        error.what());
    }
  }

  yoga_cam_sub::CameraParameters camera_parameters_;
  yoga_cam_sub::CameraCalibration calibration_;
  cv::Size current_frame_size_;
  std::string distortion_model_;
  std::vector<double> distortion_coefficients_;
  std::vector<double> camera_matrix_;
  std::vector<double> rectification_matrix_;
  std::vector<double> projection_matrix_;
  std::size_t published_frames_;
  std::size_t failed_reads_;
  int active_backend_;

  cv::VideoCapture cap_;
  rclcpp::Publisher<sensor_msgs::msg::Image>::SharedPtr image_pub_;
  rclcpp::Publisher<sensor_msgs::msg::CameraInfo>::SharedPtr camera_info_pub_;
  rclcpp::TimerBase::SharedPtr timer_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);

  try {
    auto node = std::make_shared<CameraPublisher>();
    rclcpp::spin(node);
  } catch (const std::exception & error) {
    RCLCPP_FATAL(
      rclcpp::get_logger("camera_publisher"),
      "Узел camera_publisher завершился с ошибкой: %s",
      error.what());
    rclcpp::shutdown();
    return 1;
  }

  rclcpp::shutdown();
  return 0;
}
