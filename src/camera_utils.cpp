#include "yoga_cam_sub/camera_utils.hpp"

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <iterator>
#include <sstream>
#include <stdexcept>

#include <opencv2/core/persistence.hpp>
#include <opencv2/imgproc.hpp>
#include <opencv2/videoio.hpp>

namespace yoga_cam_sub
{
namespace
{

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

cv::FileNode require_node(const cv::FileStorage & storage, const std::string & key)
{
  const cv::FileNode node = storage[key];
  if (node.empty()) {
    throw std::invalid_argument("В YAML-файле отсутствует обязательное поле '" + key + "'.");
  }

  return node;
}

int read_positive_int(const cv::FileStorage & storage, const std::string & key)
{
  const cv::FileNode node = require_node(storage, key);
  const int value = static_cast<int>(node);
  if (value <= 0) {
    throw std::invalid_argument("Поле '" + key + "' должно быть положительным.");
  }

  return value;
}

std::vector<double> read_sequence(const cv::FileStorage & storage, const std::string & key)
{
  const cv::FileNode root = require_node(storage, key);
  cv::FileNode data = root;

  // `camera_calibration` пишет матрицы как map с `rows/cols/data`, но для тестов
  // и вспомогательных сценариев поддерживаем и прямой массив значений.
  if (root.isMap()) {
    data = root["data"];
    if (data.empty()) {
      throw std::invalid_argument("Поле '" + key + "' должно содержать вложенный массив data.");
    }
  }

  if (!data.isSeq()) {
    throw std::invalid_argument("Поле '" + key + "' должно быть массивом чисел.");
  }

  std::vector<double> values;
  values.reserve(data.size());
  for (const auto & value : data) {
    values.push_back(static_cast<double>(value.real()));
  }

  return values;
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
  if (calibration.calibration_image_size.width <= 0 || calibration.calibration_image_size.height <= 0) {
    errors.emplace_back("Размер калибровки должен быть положительным.");
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

  // До реальной калибровки публикуем согласованный шаблон, зависящий от размера кадра.
  CameraCalibration calibration;
  calibration.calibration_image_size = image_size;
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

CameraCalibration load_camera_calibration_file(const std::string & file_path)
{
  if (file_path.empty()) {
    throw std::invalid_argument("Путь к calibration_file не должен быть пустым.");
  }

  const std::filesystem::path calibration_path(file_path);
  if (!std::filesystem::exists(calibration_path)) {
    throw std::invalid_argument("Файл калибровки не найден: " + calibration_path.string());
  }

  cv::FileStorage storage(calibration_path.string(), cv::FileStorage::READ);
  if (!storage.isOpened()) {
    throw std::invalid_argument("Не удалось открыть YAML-файл калибровки: " + calibration_path.string());
  }

  CameraCalibration calibration;
  calibration.calibration_image_size = cv::Size(
    read_positive_int(storage, "image_width"),
    read_positive_int(storage, "image_height"));

  const cv::FileNode camera_name_node = storage["camera_name"];
  calibration.camera_name = camera_name_node.empty()
    ? calibration_path.stem().string()
    : static_cast<std::string>(camera_name_node);
  calibration.distortion_model = static_cast<std::string>(require_node(storage, "distortion_model"));
  calibration.d = read_sequence(storage, "distortion_coefficients");
  calibration.k = to_array<9>(read_sequence(storage, "camera_matrix"), "camera_matrix");
  calibration.r = to_array<9>(read_sequence(storage, "rectification_matrix"), "rectification_matrix");
  calibration.p = to_array<12>(read_sequence(storage, "projection_matrix"), "projection_matrix");

  const auto errors = validate_calibration(calibration);
  if (!errors.empty()) {
    std::ostringstream stream;
    stream << "Некорректный YAML-файл калибровки:";
    for (const auto & error : errors) {
      stream << ' ' << error;
    }
    throw std::invalid_argument(stream.str());
  }

  return calibration;
}

CameraCalibration scale_camera_calibration(
  const CameraCalibration & calibration,
  const cv::Size & image_size)
{
  if (image_size.width <= 0 || image_size.height <= 0) {
    throw std::invalid_argument("Размер изображения для масштабирования калибровки должен быть положительным.");
  }

  const auto errors = validate_calibration(calibration);
  if (!errors.empty()) {
    std::ostringstream stream;
    stream << "Невозможно масштабировать некорректную калибровку:";
    for (const auto & error : errors) {
      stream << ' ' << error;
    }
    throw std::invalid_argument(stream.str());
  }

  if (calibration.calibration_image_size == image_size) {
    return calibration;
  }

  const double scale_x =
    static_cast<double>(image_size.width) / static_cast<double>(calibration.calibration_image_size.width);
  const double scale_y =
    static_cast<double>(image_size.height) / static_cast<double>(calibration.calibration_image_size.height);

  CameraCalibration scaled = calibration;
  scaled.calibration_image_size = image_size;

  // Масштабируем только те элементы K и P, которые выражены в пикселях.
  scaled.k[0] *= scale_x;
  scaled.k[2] *= scale_x;
  scaled.k[4] *= scale_y;
  scaled.k[5] *= scale_y;

  scaled.p[0] *= scale_x;
  scaled.p[2] *= scale_x;
  scaled.p[3] *= scale_x;
  scaled.p[5] *= scale_y;
  scaled.p[6] *= scale_y;
  scaled.p[7] *= scale_y;

  return scaled;
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
  stream << "Неподдерживаемый тип кадра OpenCV: " << frame.type()
         << ". Ожидается CV_8UC1, CV_8UC3 или CV_8UC4.";
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

  // ROI-кадры OpenCV могут иметь лишний шаг строки, поэтому копируем их построчно.
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

std::vector<int> build_video_backend_priority(bool prefer_msmf)
{
  if (prefer_msmf) {
    return {cv::CAP_MSMF, cv::CAP_ANY};
  }

  return {cv::CAP_ANY, cv::CAP_MSMF};
}

std::vector<int> build_recovery_backend_priority(
  const std::vector<int> & preferred_backends,
  int active_backend)
{
  std::vector<int> recovery_backends;
  recovery_backends.reserve(preferred_backends.size() + 1);

  // Сначала пробуем альтернативные backend-ы, а уже потом повторно открываем текущий,
  // чтобы быстрее выбраться из состояния, когда backend открыл устройство, но не читает кадры.
  for (const int backend : preferred_backends) {
    if (backend != active_backend) {
      recovery_backends.push_back(backend);
    }
  }
  recovery_backends.push_back(active_backend);

  std::vector<int> unique_backends;
  unique_backends.reserve(recovery_backends.size());
  for (const int backend : recovery_backends) {
    if (std::find(unique_backends.begin(), unique_backends.end(), backend) == unique_backends.end()) {
      unique_backends.push_back(backend);
    }
  }

  return unique_backends;
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
