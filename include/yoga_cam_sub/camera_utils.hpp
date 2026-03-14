#ifndef YOGA_CAM_SUB__CAMERA_UTILS_HPP_
#define YOGA_CAM_SUB__CAMERA_UTILS_HPP_

#include <array>
#include <string>
#include <vector>

#include <opencv2/core/mat.hpp>
#include <opencv2/core/types.hpp>

#include "rclcpp/time.hpp"
#include "sensor_msgs/msg/camera_info.hpp"
#include "sensor_msgs/msg/image.hpp"

namespace yoga_cam_sub
{

// Параметры runtime-конфигурации узла камеры.
struct CameraParameters
{
  int device_index{0};
  int width{640};
  int height{360};
  double fps{30.0};
  std::string frame_id{"camera_optical_frame"};
  std::string image_topic{"/camera/image_raw"};
  std::string camera_info_topic{"/camera/camera_info"};
  bool use_msmf{true};
  int max_frames{0};
};

// Калибровка, уже подготовленная к публикации в CameraInfo.
struct CameraCalibration
{
  // Имя камеры приходит из YAML `camera_calibration` и полезно для диагностики.
  std::string camera_name{"camera"};
  // Размер, в котором исходно была получена калибровка.
  cv::Size calibration_image_size{};
  std::string distortion_model{"plumb_bob"};
  std::vector<double> d{0.0, 0.0, 0.0, 0.0, 0.0};
  std::array<double, 9> k{{1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}};
  std::array<double, 9> r{{1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}};
  std::array<double, 12> p{{1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0}};
};

// Возвращает список ошибок конфигурации узла камеры.
std::vector<std::string> validate_camera_parameters(const CameraParameters & parameters);

// Возвращает список ошибок калибровки перед публикацией CameraInfo.
std::vector<std::string> validate_calibration(const CameraCalibration & calibration);

// Строит безопасную шаблонную калибровку по размеру кадра.
CameraCalibration make_default_calibration(const cv::Size & image_size);

// Объединяет шаблонную калибровку с пользовательскими override-параметрами.
CameraCalibration merge_calibration_overrides(
  const cv::Size & image_size,
  const std::string & distortion_model,
  const std::vector<double> & distortion_coefficients,
  const std::vector<double> & camera_matrix,
  const std::vector<double> & rectification_matrix,
  const std::vector<double> & projection_matrix);

// Загружает стандартный YAML-файл, сформированный `camera_calibration`.
CameraCalibration load_camera_calibration_file(const std::string & file_path);

// Масштабирует калибровку на новое разрешение, если поток идёт не в исходном размере.
CameraCalibration scale_camera_calibration(
  const CameraCalibration & calibration,
  const cv::Size & image_size);

// Приводит кадр OpenCV к формату CV_8UC3 для публикации как bgr8.
cv::Mat prepare_frame_for_publish(const cv::Mat & frame);

sensor_msgs::msg::Image build_image_message(
  const cv::Mat & frame,
  const std::string & frame_id,
  const rclcpp::Time & stamp);

sensor_msgs::msg::CameraInfo build_camera_info_message(
  const cv::Size & image_size,
  const std::string & frame_id,
  const rclcpp::Time & stamp,
  const CameraCalibration & calibration);

// Возвращает предпочтительный порядок backend OpenCV для первичного открытия камеры.
std::vector<int> build_video_backend_priority(bool prefer_msmf);

// Возвращает порядок backend-ов для восстановления после серии ошибок чтения.
std::vector<int> build_recovery_backend_priority(
  const std::vector<int> & preferred_backends,
  int active_backend);

// Возвращает понятное имя backend OpenCV для логов и диагностики.
std::string describe_video_backend(int backend);

}  // namespace yoga_cam_sub

#endif  // YOGA_CAM_SUB__CAMERA_UTILS_HPP_
