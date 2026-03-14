#ifndef YOGA_CAM_SUB__STREAM_DIAGNOSTICS_HPP_
#define YOGA_CAM_SUB__STREAM_DIAGNOSTICS_HPP_

#include <cstdint>
#include <string>
#include <vector>

#include "sensor_msgs/msg/camera_info.hpp"
#include "sensor_msgs/msg/image.hpp"

namespace yoga_cam_sub
{

// Сводка по временному профилю входного видеопотока.
struct StreamTimingStatistics
{
  std::size_t intervals{0};
  double average_fps{0.0};
  double mean_period_ms{0.0};
  double min_period_ms{0.0};
  double max_period_ms{0.0};
  double stddev_period_ms{0.0};
};

// Считает средний FPS и джиттер по последовательности timestamp в наносекундах.
StreamTimingStatistics calculate_timing_statistics(const std::vector<std::int64_t> & timestamps_ns);

// Проверяет согласованность Image и CameraInfo перед подключением SLAM.
std::vector<std::string> validate_image_and_camera_info(
  const sensor_msgs::msg::Image & image,
  const sensor_msgs::msg::CameraInfo & camera_info);

// Возвращает true, если CameraInfo совпадает с нашим шаблоном по умолчанию.
bool camera_info_matches_template(const sensor_msgs::msg::CameraInfo & camera_info);

}  // namespace yoga_cam_sub

#endif  // YOGA_CAM_SUB__STREAM_DIAGNOSTICS_HPP_
