#include <chrono>
#include <cmath>
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
    preload_calibration_source();

    // Для камеры используем SensorDataQoS: downstream consumer-ы вроде preflight,
    // feature-monitor и будущего SLAM backend должны видеть поток с минимальной
    // latency, а не ждать надёжной доставки старых кадров.
    const auto qos = rclcpp::SensorDataQoS();
    image_pub_ = this->create_publisher<sensor_msgs::msg::Image>(camera_parameters_.image_topic, qos);
    camera_info_pub_ =
      this->create_publisher<sensor_msgs::msg::CameraInfo>(camera_parameters_.camera_info_topic, qos);

    open_camera();

    // Период таймера привязываем к целевому FPS, чтобы и live-run, и bag capture
    // шли из одной и той же конфигурации, которую потом анализируют preflight/report.
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
    // Сначала читаем runtime-параметры самой камеры и топиков, а затем отдельным
    // блоком - источник калибровки. Это упрощает диагностику в логах при запуске.
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
    calibration_file_ = this->declare_parameter<std::string>("calibration_file", "");

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
    if (!calibration_file_.empty()) {
      RCLCPP_INFO(
        this->get_logger(),
        "Задан внешний файл калибровки calibration_file=%s.",
        calibration_file_.c_str());
    }
  }

  void validate_parameters()
  {
    // Fail fast на некорректной конфигурации важен для automation-скриптов:
    // лучше упасть до открытия камеры, чем получить неочевидную runtime-ошибку.
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

  bool has_inline_calibration_settings() const
  {
    // Inline-калибровка считается заданной, если пользователь переопределил хотя бы
    // один блок матриц/коэффициентов. При наличии calibration_file приоритет всё равно
    // остаётся за файлом, чтобы не смешивать два источника правды.
    return distortion_model_ != "plumb_bob" ||
      !distortion_coefficients_.empty() ||
      !camera_matrix_.empty() ||
      !rectification_matrix_.empty() ||
      !projection_matrix_.empty();
  }

  void preload_calibration_source()
  {
    if (calibration_file_.empty()) {
      return;
    }

    // Загружаем файл один раз при старте, чтобы любые ошибки увидеть до открытия камеры.
    file_calibration_ = yoga_cam_sub::load_camera_calibration_file(calibration_file_);
    has_calibration_file_ = true;

    if (has_inline_calibration_settings()) {
      RCLCPP_WARN(
        this->get_logger(),
        "Параметр calibration_file задан, поэтому inline-параметры калибровки будут проигнорированы.");
    }

    RCLCPP_INFO(
      this->get_logger(),
      "Загружен calibration_file=%s camera_name=%s source_width=%d source_height=%d distortion_model=%s.",
      calibration_file_.c_str(),
      file_calibration_.camera_name.c_str(),
      file_calibration_.calibration_image_size.width,
      file_calibration_.calibration_image_size.height,
      file_calibration_.distortion_model.c_str());
  }

  void open_camera()
  {
    // Для Windows-ноутбуков используем один и тот же порядок backend-ов и при старте,
    // и при runtime-восстановлении после серии ошибок чтения.
    preferred_backends_ = yoga_cam_sub::build_video_backend_priority(camera_parameters_.use_msmf);

    for (const int backend : preferred_backends_) {
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

  bool attempt_recover_after_failed_reads()
  {
    if (preferred_backends_.empty()) {
      return false;
    }

    const auto recovery_backends =
      yoga_cam_sub::build_recovery_backend_priority(preferred_backends_, active_backend_);

    RCLCPP_WARN(
      this->get_logger(),
      "После %zu подряд ошибок чтения пробуем восстановить камеру. Текущий backend=%s.",
      failed_reads_,
      yoga_cam_sub::describe_video_backend(active_backend_).c_str());

    for (const int backend : recovery_backends) {
      if (try_open_camera(backend)) {
        active_backend_ = backend;
        failed_reads_ = 0;
        RCLCPP_INFO(
          this->get_logger(),
          "Восстановление камеры успешно. Новый backend=%s.",
          yoga_cam_sub::describe_video_backend(active_backend_).c_str());
        return true;
      }
    }

    RCLCPP_ERROR(
      this->get_logger(),
      "Не удалось восстановить чтение камеры после %zu подряд ошибок.",
      failed_reads_);
    return false;
  }

  void refresh_calibration_if_needed(const cv::Size & image_size)
  {
    if (image_size == current_frame_size_) {
      return;
    }

    if (has_calibration_file_) {
      // Реальная калибровка сохраняется в исходном размере и при необходимости
      // масштабируется на runtime-разрешение потока без ручного пересчёта матриц.
      calibration_ = yoga_cam_sub::scale_camera_calibration(file_calibration_, image_size);

      const double scale_x = static_cast<double>(image_size.width) /
        static_cast<double>(file_calibration_.calibration_image_size.width);
      const double scale_y = static_cast<double>(image_size.height) /
        static_cast<double>(file_calibration_.calibration_image_size.height);

      if (std::abs(scale_x - scale_y) > 1e-6) {
        RCLCPP_WARN(
          this->get_logger(),
          "Размер потока %dx%d отличается по aspect ratio от калибровки %dx%d. Калибровка будет масштабирована неравномерно; для SLAM лучше перекалибровать камеру.",
          image_size.width,
          image_size.height,
          file_calibration_.calibration_image_size.width,
          file_calibration_.calibration_image_size.height);
      } else if (file_calibration_.calibration_image_size != image_size) {
        RCLCPP_INFO(
          this->get_logger(),
          "Калибровка из файла будет масштабирована с %dx%d на %dx%d (scale_x=%.3f scale_y=%.3f).",
          file_calibration_.calibration_image_size.width,
          file_calibration_.calibration_image_size.height,
          image_size.width,
          image_size.height,
          scale_x,
          scale_y);
      }
    } else {
      // CameraInfo пересобирается только при изменении фактического размера кадра.
      calibration_ = yoga_cam_sub::merge_calibration_overrides(
        image_size,
        distortion_model_,
        distortion_coefficients_,
        camera_matrix_,
        rectification_matrix_,
        projection_matrix_);
    }
    current_frame_size_ = image_size;

    RCLCPP_INFO(
      this->get_logger(),
      "Подготовлен CameraInfo для размера %dx%d. Значения калибровки %s.",
      image_size.width,
      image_size.height,
      has_calibration_file_ ? "загружены из calibration_file" :
      (camera_matrix_.empty() ? "взяты из шаблона по умолчанию" : "загружены из параметров"));
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

      // Если backend зависает после успешного открытия устройства, пробуем мягко
      // переключиться на альтернативный backend и продолжить публикацию без перезапуска узла.
      if (failed_reads_ % 30 == 0) {
        (void)attempt_recover_after_failed_reads();
      }
      return;
    }

    try {
      cv::Mat frame = yoga_cam_sub::prepare_frame_for_publish(raw_frame);
      refresh_calibration_if_needed(frame.size());

      // Image и CameraInfo публикуем с одним и тем же stamp в одном callback-е.
      // Для downstream SLAM это минимальный контракт синхронности, даже если
      // upstream-камера не даёт отдельный hardware timestamp.
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
  std::string calibration_file_;
  std::size_t published_frames_;
  std::size_t failed_reads_;
  int active_backend_;
  std::vector<int> preferred_backends_;
  bool has_calibration_file_{false};
  yoga_cam_sub::CameraCalibration file_calibration_;

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
