#include "yoga_cam_sub/camera_utils.hpp"

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <sstream>
#include <stdexcept>

#include <opencv2/imgproc.hpp>
#include <opencv2/videoio.hpp>

namespace yoga_cam_sub
{
namespace
{

template<typename ArrayT>
std::vector<double> to_vector(const ArrayT & values)
{
  return std::vector<double>(values.begin(), values.end());
}

template<std::size_t Size>
std::array<double, Size> to_array(
  const std::vector<double> & values,
  const std::string & parameter_name)
{
  if (values.size() != Size) {
    std::ostringstream stream;
    stream << "Параметр '" << parameter_name << "' должен содержать " << Size << " значений.";
    throw std::invalid_argument(stream.str());
  }

  std::array<double, Size> result{};
  std::copy(values.begin(), values.end(), result.begin());
  return result;
}

void ensure_non_empty_frame(const cv::Mat & frame)
{
  if (frame.empty()) {
    throw std::invalid_argument("Невозможно сформировать сообщение из пустого кадра.");
  }
}

}  // namespace

std::vector<std::string> validate_camera_parameters(const CameraParameters & parameters)
{
  std::vector<std::string> errors;

  if (parameters.device_index < 0) {
    errors.emplace_back("Индекс камеры должен быть неотрицательным.");
  }
  if (parameters.width <= 0) {
    errors.emplace_back("Ширина кадра должна быть больше нуля.");
  }
  if (parameters.height <= 0) {
    errors.emplace_back("Высота кадра должна быть больше нуля.");
  }
  if (parameters.fps <= 0.0) {
    errors.emplace_back("Частота кадров должна быть больше нуля.");
  }
  if (parameters.frame_id.empty()) {
    errors.emplace_back("Параметр frame_id не должен быть пустым.");
  }
  if (parameters.image_topic.empty()) {
    errors.emplace_back("Имя топика изображения не должно быть пустым.");
  }
  if (parameters.camera_info_topic.empty()) {
    errors.emplace_back("Имя топика CameraInfo не должно быть пустым.");
  }
  if (parameters.max_frames < 0) {
    errors.emplace_back("Параметр max_frames не может быть отрицательным.");
  }

  return errors;
}

std::vector<std::string> validate_calibration(const CameraCalibration & calibration)
{
  std::vector<std::string> errors;

  if (calibration.distortion_model.empty()) {
    errors.emplace_back("Модель дисторсии не должна быть пустой.");
  }
  if (calibration.d.empty()) {
    errors.emplace_back("Массив коэффициентов дисторсии не должен быть пустым.");
  }
  if (calibration.k[8] == 0.0) {
    errors.emplace_back("Матрица K должна иметь ненулевой элемент K[8].");
  }
  if (calibration.r[8] == 0.0) {
    errors.emplace_back("Матрица R должна иметь ненулевой элемент R[8].");
  }
  if (calibration.p[10] == 0.0) {
    errors.emplace_back("Матрица P должна иметь ненулевой элемент P[10].");
  }

  return errors;
}

CameraCalibration make_default_calibration(const cv::Size & image_size)
{
  if (image_size.width <= 0 || image_size.height <= 0) {
    throw std::invalid_argument("Размер изображения для CameraInfo должен быть положительным.");
  }

  const double fx = static_cast<double>(image_size.width);
  const double fy = static_cast<double>(image_size.height);
  const double cx = static_cast<double>(image_size.width - 1) / 2.0;
  const double cy = static_cast<double>(image_size.height - 1) / 2.0;

  CameraCalibration calibration;
  calibration.k = {{fx, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0}};
  calibration.r = {{1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0}};
  calibration.p = {{fx, 0.0, cx, 0.0, 0.0, fy, cy, 0.0, 0.0, 0.0, 1.0, 0.0}};
  return calibration;
}

CameraCalibration merge_calibration_overrides(
  const cv::Size & image_size,
  const std::string & distortion_model,
  const std::vector<double> & distortion_coefficients,
  const std::vector<double> & camera_matrix,
  const std::vector<double> & rectification_matrix,
  const std::vector<double> & projection_matrix)
{
  CameraCalibration calibration = make_default_calibration(image_size);

  if (!distortion_model.empty()) {
    calibration.distortion_model = distortion_model;
  }
  if (!distortion_coefficients.empty()) {
    calibration.d = distortion_coefficients;
  }
  if (!camera_matrix.empty()) {
    calibration.k = to_array<9>(camera_matrix, "camera_matrix");
  }
  if (!rectification_matrix.empty()) {
    calibration.r = to_array<9>(rectification_matrix, "rectification_matrix");
  }
  if (!projection_matrix.empty()) {
    calibration.p = to_array<12>(projection_matrix, "projection_matrix");
  }

  const auto errors = validate_calibration(calibration);
  if (!errors.empty()) {
    std::ostringstream stream;
    stream << "Некорректная калибровка камеры:";
    for (const auto & error : errors) {
      stream << ' ' << error;
    }
    throw std::invalid_argument(stream.str());
  }

  return calibration;
}

cv::Mat prepare_frame_for_publish(const cv::Mat & frame)
{
  ensure_non_empty_frame(frame);

  if (frame.type() == CV_8UC3) {
    return frame;
  }

  cv::Mat converted;
  if (frame.type() == CV_8UC1) {
    cv::cvtColor(frame, converted, cv::COLOR_GRAY2BGR);
    return converted;
  }
  if (frame.type() == CV_8UC4) {
    cv::cvtColor(frame, converted, cv::COLOR_BGRA2BGR);
    return converted;
  }

  std::ostringstream stream;
  stream << "Неподдерживаемый тип кадра OpenCV: " << frame.type() << ". Ожидается CV_8UC1, CV_8UC3 или CV_8UC4.";
  throw std::invalid_argument(stream.str());
}

sensor_msgs::msg::Image build_image_message(
  const cv::Mat & frame,
  const std::string & frame_id,
  const rclcpp::Time & stamp)
{
  ensure_non_empty_frame(frame);

  if (frame.type() != CV_8UC3) {
    throw std::invalid_argument("Для публикации изображения ожидается кадр в формате CV_8UC3.");
  }

  sensor_msgs::msg::Image message;
  message.header.stamp = stamp;
  message.header.frame_id = frame_id;
  message.height = static_cast<uint32_t>(frame.rows);
  message.width = static_cast<uint32_t>(frame.cols);
  message.encoding = "bgr8";
  message.is_bigendian = false;
  const auto row_step = static_cast<std::size_t>(frame.cols) * frame.elemSize();
  message.step = static_cast<sensor_msgs::msg::Image::_step_type>(row_step);
  message.data.resize(static_cast<std::size_t>(frame.rows) * row_step);

  if (frame.isContinuous() && row_step == frame.step) {
    std::copy(frame.datastart, frame.dataend, message.data.begin());
    return message;
  }

  for (int row = 0; row < frame.rows; ++row) {
    const auto * row_begin = frame.ptr<std::uint8_t>(row);
    std::copy(
      row_begin,
      row_begin + row_step,
      message.data.begin() + static_cast<std::ptrdiff_t>(row) * row_step);
  }

  return message;
}

sensor_msgs::msg::CameraInfo build_camera_info_message(
  const cv::Size & image_size,
  const std::string & frame_id,
  const rclcpp::Time & stamp,
  const CameraCalibration & calibration)
{
  if (image_size.width <= 0 || image_size.height <= 0) {
    throw std::invalid_argument("Размер изображения в CameraInfo должен быть положительным.");
  }

  const auto errors = validate_calibration(calibration);
  if (!errors.empty()) {
    std::ostringstream stream;
    stream << "Невозможно сформировать CameraInfo:";
    for (const auto & error : errors) {
      stream << ' ' << error;
    }
    throw std::invalid_argument(stream.str());
  }

  sensor_msgs::msg::CameraInfo message;
  message.header.stamp = stamp;
  message.header.frame_id = frame_id;
  message.width = static_cast<uint32_t>(image_size.width);
  message.height = static_cast<uint32_t>(image_size.height);
  message.distortion_model = calibration.distortion_model;
  message.d = calibration.d;
  std::copy(calibration.k.begin(), calibration.k.end(), message.k.begin());
  std::copy(calibration.r.begin(), calibration.r.end(), message.r.begin());
  std::copy(calibration.p.begin(), calibration.p.end(), message.p.begin());
  return message;
}

std::string describe_video_backend(int backend)
{
  switch (backend) {
    case cv::CAP_ANY:
      return "CAP_ANY";
    case cv::CAP_MSMF:
      return "CAP_MSMF";
    case cv::CAP_DSHOW:
      return "CAP_DSHOW";
    case cv::CAP_VFW:
      return "CAP_VFW";
    default:
      return "Неизвестный backend (" + std::to_string(backend) + ')';
  }
}

}  // namespace yoga_cam_sub
