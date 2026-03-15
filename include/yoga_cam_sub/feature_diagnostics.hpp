#ifndef YOGA_CAM_SUB__FEATURE_DIAGNOSTICS_HPP_
#define YOGA_CAM_SUB__FEATURE_DIAGNOSTICS_HPP_

#include <cstddef>
#include <string>
#include <vector>

#include <opencv2/core/mat.hpp>

#include "sensor_msgs/msg/image.hpp"

namespace yoga_cam_sub
{

// Метрики одного кадра, которые помогают оценить пригодность потока для monocular SLAM.
struct FeatureFrameMetrics
{
  std::size_t keypoints{0};
  double mean_keypoint_response{0.0};
  double grid_coverage_ratio{0.0};
  double blur_score{0.0};
  double brightness_mean{0.0};
  double brightness_stddev{0.0};
};

// Пороговые значения для быстрой проверки качества потока перед запуском SLAM.
struct FeatureMonitorThresholds
{
  int min_average_keypoints{150};
  double min_average_grid_coverage_ratio{0.35};
  double min_average_blur_score{80.0};
  double min_average_brightness_mean{25.0};
};

// Агрегированная сводка по нескольким кадрам.
struct FeatureMonitorSummary
{
  std::size_t frames{0};
  double average_keypoints{0.0};
  std::size_t min_keypoints{0};
  double average_keypoint_response{0.0};
  double average_grid_coverage_ratio{0.0};
  double average_blur_score{0.0};
  double average_brightness_mean{0.0};
  double average_brightness_stddev{0.0};
};

// Преобразует sensor_msgs/Image в BGR-кадр OpenCV для единой downstream-обработки.
cv::Mat convert_image_message_to_bgr(const sensor_msgs::msg::Image & message);

// Считает feature- и quality-метрики по одному кадру.
FeatureFrameMetrics analyze_feature_frame(
  const cv::Mat & frame,
  int max_features = 500,
  int grid_rows = 4,
  int grid_cols = 4);

// Агрегирует метрики нескольких кадров в summary для логов и отчётов.
FeatureMonitorSummary summarize_feature_metrics(const std::vector<FeatureFrameMetrics> & frame_metrics);

// Проверяет, что summary не проваливается по базовым порогам качества.
std::vector<std::string> validate_feature_summary(
  const FeatureMonitorSummary & summary,
  const FeatureMonitorThresholds & thresholds);

}  // namespace yoga_cam_sub

#endif  // YOGA_CAM_SUB__FEATURE_DIAGNOSTICS_HPP_
