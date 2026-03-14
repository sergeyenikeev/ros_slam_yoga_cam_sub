#include <cstdint>
#include <exception>
#include <memory>
#include <stdexcept>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "yoga_cam_sub/camera_utils.hpp"

class CameraCalibrationInspector : public rclcpp::Node
{
public:
  CameraCalibrationInspector()
  : Node("camera_calibration_inspector")
  {
    calibration_file_ = this->declare_parameter<std::string>("calibration_file", "");
    target_width_ = static_cast<int>(this->declare_parameter<std::int64_t>("target_width", 0));
    target_height_ = static_cast<int>(this->declare_parameter<std::int64_t>("target_height", 0));

    if (calibration_file_.empty()) {
      throw std::invalid_argument("Параметр calibration_file обязателен для camera_calibration_inspector.");
    }
    if ((target_width_ == 0) != (target_height_ == 0)) {
      throw std::invalid_argument("Параметры target_width и target_height должны задаваться вместе.");
    }

    inspect();
  }

private:
  void inspect()
  {
    const auto source_calibration = yoga_cam_sub::load_camera_calibration_file(calibration_file_);

    RCLCPP_INFO(
      this->get_logger(),
      "Файл калибровки успешно загружен: calibration_file=%s camera_name=%s source_width=%d source_height=%d distortion_model=%s d_size=%zu.",
      calibration_file_.c_str(),
      source_calibration.camera_name.c_str(),
      source_calibration.calibration_image_size.width,
      source_calibration.calibration_image_size.height,
      source_calibration.distortion_model.c_str(),
      source_calibration.d.size());
    RCLCPP_INFO(
      this->get_logger(),
      "Исходные параметры: fx=%.6f fy=%.6f cx=%.6f cy=%.6f.",
      source_calibration.k[0],
      source_calibration.k[4],
      source_calibration.k[2],
      source_calibration.k[5]);

    if (target_width_ > 0 && target_height_ > 0) {
      // Узел позволяет заранее проверить, как калибровка будет выглядеть на другом runtime-разрешении.
      const auto scaled = yoga_cam_sub::scale_camera_calibration(
        source_calibration,
        cv::Size(target_width_, target_height_));
      RCLCPP_INFO(
        this->get_logger(),
        "Масштабированная калибровка: target_width=%d target_height=%d fx=%.6f fy=%.6f cx=%.6f cy=%.6f.",
        target_width_,
        target_height_,
        scaled.k[0],
        scaled.k[4],
        scaled.k[2],
        scaled.k[5]);
    }
  }

  std::string calibration_file_;
  int target_width_;
  int target_height_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);

  try {
    auto node = std::make_shared<CameraCalibrationInspector>();
    (void)node;
    rclcpp::shutdown();
    return 0;
  } catch (const std::exception & error) {
    RCLCPP_FATAL(
      rclcpp::get_logger("camera_calibration_inspector"),
      "Проверка файла калибровки завершилась с ошибкой: %s",
      error.what());
    rclcpp::shutdown();
    return 1;
  }
}
