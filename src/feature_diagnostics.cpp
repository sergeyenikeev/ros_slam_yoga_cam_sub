#include "yoga_cam_sub/feature_diagnostics.hpp"

#include <algorithm>
#include <numeric>
#include <stdexcept>

#include <opencv2/core.hpp>
#include <opencv2/features2d.hpp>
#include <opencv2/imgproc.hpp>

namespace yoga_cam_sub
{
namespace
{

int expected_channel_count(const std::string & encoding)
{
  if (encoding == "bgr8" || encoding == "rgb8") {
    return 3;
  }
  if (encoding == "mono8") {
    return 1;
  }
  if (encoding == "bgra8" || encoding == "rgba8") {
    return 4;
  }

  throw std::invalid_argument("Неподдерживаемый encoding для feature diagnostics: " + encoding);
}

cv::Mat make_shared_image_view(const sensor_msgs::msg::Image & message, int channels)
{
  if (message.width == 0U || message.height == 0U) {
    throw std::invalid_argument("Image содержит нулевой размер кадра.");
  }

  const auto expected_step = static_cast<std::size_t>(message.width) * static_cast<std::size_t>(channels);
  if (message.step < expected_step) {
    throw std::invalid_argument("Image содержит некорректный step для указанного encoding.");
  }

  const auto required_size = static_cast<std::size_t>(message.step) * static_cast<std::size_t>(message.height);
  if (message.data.size() < required_size) {
    throw std::invalid_argument("Image содержит меньше данных, чем требуется по размеру кадра и step.");
  }

  const int type = CV_MAKETYPE(CV_8U, channels);
  return cv::Mat(
    static_cast<int>(message.height),
    static_cast<int>(message.width),
    type,
    const_cast<unsigned char *>(message.data.data()),
    static_cast<std::size_t>(message.step));
}

cv::Mat ensure_bgr_frame(const cv::Mat & frame)
{
  if (frame.empty()) {
    throw std::invalid_argument("Нельзя анализировать пустой кадр.");
  }

  if (frame.type() == CV_8UC3) {
    return frame.clone();
  }
  if (frame.type() == CV_8UC1) {
    cv::Mat converted;
    cv::cvtColor(frame, converted, cv::COLOR_GRAY2BGR);
    return converted;
  }
  if (frame.type() == CV_8UC4) {
    cv::Mat converted;
    cv::cvtColor(frame, converted, cv::COLOR_BGRA2BGR);
    return converted;
  }

  throw std::invalid_argument("Feature diagnostics поддерживает только mono8, bgr8 и bgra8 кадры OpenCV.");
}

cv::Mat to_grayscale(const cv::Mat & frame_bgr)
{
  cv::Mat gray;
  cv::cvtColor(frame_bgr, gray, cv::COLOR_BGR2GRAY);
  return gray;
}

}  // namespace

cv::Mat convert_image_message_to_bgr(const sensor_msgs::msg::Image & message)
{
  const int channels = expected_channel_count(message.encoding);
  const cv::Mat raw_frame = make_shared_image_view(message, channels);

  if (message.encoding == "bgr8") {
    return raw_frame.clone();
  }
  if (message.encoding == "rgb8") {
    cv::Mat converted;
    cv::cvtColor(raw_frame, converted, cv::COLOR_RGB2BGR);
    return converted;
  }
  if (message.encoding == "mono8") {
    cv::Mat converted;
    cv::cvtColor(raw_frame, converted, cv::COLOR_GRAY2BGR);
    return converted;
  }
  if (message.encoding == "bgra8") {
    cv::Mat converted;
    cv::cvtColor(raw_frame, converted, cv::COLOR_BGRA2BGR);
    return converted;
  }
  if (message.encoding == "rgba8") {
    cv::Mat converted;
    cv::cvtColor(raw_frame, converted, cv::COLOR_RGBA2BGR);
    return converted;
  }

  throw std::invalid_argument("Неподдерживаемый encoding для feature diagnostics: " + message.encoding);
}

FeatureFrameMetrics analyze_feature_frame(
  const cv::Mat & frame,
  int max_features,
  int grid_rows,
  int grid_cols)
{
  if (max_features <= 0) {
    throw std::invalid_argument("Параметр max_features должен быть положительным.");
  }
  if (grid_rows <= 0 || grid_cols <= 0) {
    throw std::invalid_argument("Размер feature-сетки должен быть положительным.");
  }

  const cv::Mat frame_bgr = ensure_bgr_frame(frame);
  const cv::Mat gray = to_grayscale(frame_bgr);

  cv::Scalar mean_brightness;
  cv::Scalar stddev_brightness;
  cv::meanStdDev(gray, mean_brightness, stddev_brightness);

  cv::Mat laplacian;
  cv::Laplacian(gray, laplacian, CV_64F);
  cv::Scalar laplacian_mean;
  cv::Scalar laplacian_stddev;
  cv::meanStdDev(laplacian, laplacian_mean, laplacian_stddev);

  auto orb = cv::ORB::create(max_features);
  std::vector<cv::KeyPoint> keypoints;
  orb->detect(gray, keypoints);

  const int total_cells = grid_rows * grid_cols;
  std::vector<bool> occupied_cells(static_cast<std::size_t>(total_cells), false);
  double response_sum = 0.0;

  const int width = gray.cols;
  const int height = gray.rows;
  for (const auto & keypoint : keypoints) {
    response_sum += static_cast<double>(keypoint.response);

    // Сетка нужна, чтобы быстро отлавливать случаи, когда все feature скучены в одном углу кадра.
    const int column = std::min(grid_cols - 1, std::max(0, static_cast<int>(keypoint.pt.x * grid_cols / width)));
    const int row = std::min(grid_rows - 1, std::max(0, static_cast<int>(keypoint.pt.y * grid_rows / height)));
    occupied_cells[static_cast<std::size_t>(row * grid_cols + column)] = true;
  }

  const auto occupied_count = static_cast<std::size_t>(
    std::count(occupied_cells.begin(), occupied_cells.end(), true));

  FeatureFrameMetrics metrics;
  metrics.keypoints = keypoints.size();
  metrics.mean_keypoint_response = keypoints.empty() ? 0.0 : response_sum / static_cast<double>(keypoints.size());
  metrics.grid_coverage_ratio = static_cast<double>(occupied_count) / static_cast<double>(total_cells);
  metrics.blur_score = laplacian_stddev[0] * laplacian_stddev[0];
  metrics.brightness_mean = mean_brightness[0];
  metrics.brightness_stddev = stddev_brightness[0];
  return metrics;
}

FeatureMonitorSummary summarize_feature_metrics(const std::vector<FeatureFrameMetrics> & frame_metrics)
{
  if (frame_metrics.empty()) {
    throw std::invalid_argument("Для summary feature-метрик нужен минимум один кадр.");
  }

  FeatureMonitorSummary summary;
  summary.frames = frame_metrics.size();
  summary.min_keypoints = frame_metrics.front().keypoints;

  for (const auto & metrics : frame_metrics) {
    summary.average_keypoints += static_cast<double>(metrics.keypoints);
    summary.average_keypoint_response += metrics.mean_keypoint_response;
    summary.average_grid_coverage_ratio += metrics.grid_coverage_ratio;
    summary.average_blur_score += metrics.blur_score;
    summary.average_brightness_mean += metrics.brightness_mean;
    summary.average_brightness_stddev += metrics.brightness_stddev;
    summary.min_keypoints = std::min(summary.min_keypoints, metrics.keypoints);
  }

  const double frames = static_cast<double>(summary.frames);
  summary.average_keypoints /= frames;
  summary.average_keypoint_response /= frames;
  summary.average_grid_coverage_ratio /= frames;
  summary.average_blur_score /= frames;
  summary.average_brightness_mean /= frames;
  summary.average_brightness_stddev /= frames;
  return summary;
}

std::vector<std::string> validate_feature_summary(
  const FeatureMonitorSummary & summary,
  const FeatureMonitorThresholds & thresholds)
{
  std::vector<std::string> errors;

  if (summary.frames == 0U) {
    errors.emplace_back("Feature summary не содержит ни одного кадра.");
    return errors;
  }
  if (thresholds.min_average_keypoints <= 0) {
    throw std::invalid_argument("Порог min_average_keypoints должен быть положительным.");
  }
  if (thresholds.min_average_grid_coverage_ratio <= 0.0 ||
    thresholds.min_average_grid_coverage_ratio > 1.0)
  {
    throw std::invalid_argument("Порог min_average_grid_coverage_ratio должен быть в диапазоне (0, 1].");
  }
  if (thresholds.min_average_blur_score <= 0.0) {
    throw std::invalid_argument("Порог min_average_blur_score должен быть больше нуля.");
  }
  if (thresholds.min_average_brightness_mean <= 0.0 ||
    thresholds.min_average_brightness_mean > 255.0)
  {
    throw std::invalid_argument("Порог min_average_brightness_mean должен быть в диапазоне (0, 255].");
  }

  if (summary.average_keypoints < static_cast<double>(thresholds.min_average_keypoints)) {
    errors.emplace_back("Среднее число keypoints ниже порога.");
  }
  if (summary.average_grid_coverage_ratio < thresholds.min_average_grid_coverage_ratio) {
    errors.emplace_back("Среднее покрытие feature-сетки ниже порога.");
  }
  if (summary.average_blur_score < thresholds.min_average_blur_score) {
    errors.emplace_back("Средняя резкость кадра ниже порога.");
  }
  if (summary.average_brightness_mean < thresholds.min_average_brightness_mean) {
    errors.emplace_back("Средняя яркость кадра ниже порога.");
  }

  return errors;
}

}  // namespace yoga_cam_sub
