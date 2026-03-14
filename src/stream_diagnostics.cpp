#include "yoga_cam_sub/stream_diagnostics.hpp"

#include <algorithm>
#include <cmath>
#include <numeric>
#include <sstream>
#include <stdexcept>

#include "yoga_cam_sub/camera_utils.hpp"

namespace yoga_cam_sub
{
namespace
{

bool nearly_equal(double left, double right, double epsilon = 1e-9)
{
  return std::abs(left - right) <= epsilon;
}

}  // namespace

StreamTimingStatistics calculate_timing_statistics(const std::vector<std::int64_t> & timestamps_ns)
{
  if (timestamps_ns.size() < 2U) {
    throw std::invalid_argument("Для расчёта временной статистики нужны минимум два timestamp.");
  }

  std::vector<double> periods_ms;
  periods_ms.reserve(timestamps_ns.size() - 1U);

  for (std::size_t index = 1; index < timestamps_ns.size(); ++index) {
    const auto delta_ns = timestamps_ns[index] - timestamps_ns[index - 1U];
    if (delta_ns <= 0) {
      throw std::invalid_argument("Timestamp изображения должны строго возрастать.");
    }

    periods_ms.push_back(static_cast<double>(delta_ns) / 1'000'000.0);
  }

  const double periods_sum = std::accumulate(periods_ms.begin(), periods_ms.end(), 0.0);
  const double mean_period_ms = periods_sum / static_cast<double>(periods_ms.size());
  const auto minmax_period = std::minmax_element(periods_ms.begin(), periods_ms.end());

  double squared_deviation_sum = 0.0;
  for (const double period_ms : periods_ms) {
    const double deviation = period_ms - mean_period_ms;
    squared_deviation_sum += deviation * deviation;
  }

  StreamTimingStatistics statistics;
  statistics.intervals = periods_ms.size();
  statistics.mean_period_ms = mean_period_ms;
  statistics.min_period_ms = *minmax_period.first;
  statistics.max_period_ms = *minmax_period.second;
  statistics.stddev_period_ms = std::sqrt(
    squared_deviation_sum / static_cast<double>(periods_ms.size()));
  statistics.average_fps = mean_period_ms > 0.0 ? 1000.0 / mean_period_ms : 0.0;
  return statistics;
}

std::vector<std::string> validate_image_and_camera_info(
  const sensor_msgs::msg::Image & image,
  const sensor_msgs::msg::CameraInfo & camera_info)
{
  std::vector<std::string> errors;

  if (image.width == 0U || image.height == 0U) {
    errors.emplace_back("Image содержит нулевой размер кадра.");
  }
  if (camera_info.width == 0U || camera_info.height == 0U) {
    errors.emplace_back("CameraInfo содержит нулевой размер кадра.");
  }
  if (image.width != camera_info.width) {
    errors.emplace_back("Ширина Image и CameraInfo не совпадает.");
  }
  if (image.height != camera_info.height) {
    errors.emplace_back("Высота Image и CameraInfo не совпадает.");
  }
  if (image.header.frame_id != camera_info.header.frame_id) {
    errors.emplace_back("frame_id в Image и CameraInfo не совпадает.");
  }
  if (image.encoding.empty()) {
    errors.emplace_back("Image имеет пустой encoding.");
  }
  if (camera_info.distortion_model.empty()) {
    errors.emplace_back("CameraInfo имеет пустой distortion_model.");
  }
  if (camera_info.k[8] == 0.0) {
    errors.emplace_back("CameraInfo содержит некорректную матрицу K.");
  }
  if (camera_info.p[10] == 0.0) {
    errors.emplace_back("CameraInfo содержит некорректную матрицу P.");
  }

  return errors;
}

bool camera_info_matches_template(const sensor_msgs::msg::CameraInfo & camera_info)
{
  if (camera_info.width == 0U || camera_info.height == 0U) {
    return false;
  }

  const auto calibration = make_default_calibration(
    cv::Size(static_cast<int>(camera_info.width), static_cast<int>(camera_info.height)));

  if (camera_info.distortion_model != calibration.distortion_model) {
    return false;
  }
  if (camera_info.d.size() != calibration.d.size()) {
    return false;
  }

  for (std::size_t index = 0; index < camera_info.d.size(); ++index) {
    if (!nearly_equal(camera_info.d[index], calibration.d[index])) {
      return false;
    }
  }
  for (std::size_t index = 0; index < calibration.k.size(); ++index) {
    if (!nearly_equal(camera_info.k[index], calibration.k[index])) {
      return false;
    }
  }
  for (std::size_t index = 0; index < calibration.r.size(); ++index) {
    if (!nearly_equal(camera_info.r[index], calibration.r[index])) {
      return false;
    }
  }
  for (std::size_t index = 0; index < calibration.p.size(); ++index) {
    if (!nearly_equal(camera_info.p[index], calibration.p[index])) {
      return false;
    }
  }

  return true;
}

}  // namespace yoga_cam_sub
