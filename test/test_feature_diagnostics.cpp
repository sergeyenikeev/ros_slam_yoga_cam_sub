#include <cstdint>
#include <stdexcept>
#include <vector>

#include <gtest/gtest.h>
#include <opencv2/imgproc.hpp>

#include "sensor_msgs/msg/image.hpp"
#include "yoga_cam_sub/feature_diagnostics.hpp"

namespace
{

sensor_msgs::msg::Image make_image_message(
  uint32_t width,
  uint32_t height,
  const std::string & encoding,
  uint32_t step,
  const std::vector<std::uint8_t> & data)
{
  sensor_msgs::msg::Image message;
  message.width = width;
  message.height = height;
  message.encoding = encoding;
  message.step = step;
  message.data = data;
  return message;
}

cv::Mat make_checkerboard_bgr(int width, int height, int cell_size)
{
  cv::Mat image(height, width, CV_8UC3, cv::Scalar(0, 0, 0));

  for (int y = 0; y < height; ++y) {
    for (int x = 0; x < width; ++x) {
      const int checker = ((x / cell_size) + (y / cell_size)) % 2;
      if (checker == 0) {
        image.at<cv::Vec3b>(y, x) = cv::Vec3b(255, 255, 255);
      }
    }
  }

  return image;
}

TEST(FeatureDiagnostics, ConvertsRgbImageMessageToBgr)
{
  const auto message = make_image_message(1U, 1U, "rgb8", 3U, {10U, 20U, 30U});
  const cv::Mat converted = yoga_cam_sub::convert_image_message_to_bgr(message);

  ASSERT_EQ(converted.type(), CV_8UC3);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[0], 30);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[1], 20);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[2], 10);
}

TEST(FeatureDiagnostics, ConvertsMonoImageMessageToBgr)
{
  const auto message = make_image_message(2U, 1U, "mono8", 2U, {7U, 9U});
  const cv::Mat converted = yoga_cam_sub::convert_image_message_to_bgr(message);

  ASSERT_EQ(converted.type(), CV_8UC3);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[0], 7);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 1)[2], 9);
}

TEST(FeatureDiagnostics, RejectsUnsupportedEncoding)
{
  const auto message = make_image_message(1U, 1U, "yuv422", 2U, {0U, 0U});
  EXPECT_THROW(yoga_cam_sub::convert_image_message_to_bgr(message), std::invalid_argument);
}

TEST(FeatureDiagnostics, RejectsInvalidStep)
{
  const auto message = make_image_message(2U, 1U, "bgr8", 2U, {1U, 2U, 3U, 4U, 5U, 6U});
  EXPECT_THROW(yoga_cam_sub::convert_image_message_to_bgr(message), std::invalid_argument);
}

TEST(FeatureDiagnostics, DetectsFeaturesOnCheckerboard)
{
  const cv::Mat checkerboard = make_checkerboard_bgr(320, 240, 20);
  const auto metrics = yoga_cam_sub::analyze_feature_frame(checkerboard, 400, 4, 4);

  EXPECT_GT(metrics.keypoints, 80U);
  EXPECT_GT(metrics.grid_coverage_ratio, 0.50);
  EXPECT_GT(metrics.blur_score, 100.0);
  EXPECT_GT(metrics.brightness_mean, 100.0);
}

TEST(FeatureDiagnostics, BlurScoreDropsForBlurredImage)
{
  const cv::Mat checkerboard = make_checkerboard_bgr(320, 240, 20);
  cv::Mat blurred;
  cv::GaussianBlur(checkerboard, blurred, cv::Size(17, 17), 5.0, 5.0);

  const auto sharp_metrics = yoga_cam_sub::analyze_feature_frame(checkerboard, 400, 4, 4);
  const auto blurred_metrics = yoga_cam_sub::analyze_feature_frame(blurred, 400, 4, 4);

  EXPECT_GT(sharp_metrics.blur_score, blurred_metrics.blur_score);
}

TEST(FeatureDiagnostics, SummarizesFrameMetrics)
{
  const std::vector<yoga_cam_sub::FeatureFrameMetrics> metrics = {
    {100U, 0.2, 0.25, 50.0, 80.0, 10.0},
    {200U, 0.4, 0.75, 150.0, 120.0, 20.0},
  };

  const auto summary = yoga_cam_sub::summarize_feature_metrics(metrics);
  EXPECT_EQ(summary.frames, 2U);
  EXPECT_DOUBLE_EQ(summary.average_keypoints, 150.0);
  EXPECT_EQ(summary.min_keypoints, 100U);
  EXPECT_DOUBLE_EQ(summary.average_keypoint_response, 0.3);
  EXPECT_DOUBLE_EQ(summary.average_grid_coverage_ratio, 0.5);
  EXPECT_DOUBLE_EQ(summary.average_blur_score, 100.0);
  EXPECT_DOUBLE_EQ(summary.average_brightness_mean, 100.0);
  EXPECT_DOUBLE_EQ(summary.average_brightness_stddev, 15.0);
}

TEST(FeatureDiagnostics, RejectsWeakFeatureSummary)
{
  yoga_cam_sub::FeatureMonitorSummary summary;
  summary.frames = 5U;
  summary.average_keypoints = 40.0;
  summary.average_grid_coverage_ratio = 0.10;
  summary.average_blur_score = 5.0;
  summary.average_brightness_mean = 3.0;

  yoga_cam_sub::FeatureMonitorThresholds thresholds;
  thresholds.min_average_keypoints = 120;
  thresholds.min_average_grid_coverage_ratio = 0.35;
  thresholds.min_average_blur_score = 80.0;
  thresholds.min_average_brightness_mean = 25.0;

  const auto errors = yoga_cam_sub::validate_feature_summary(summary, thresholds);
  ASSERT_EQ(errors.size(), 4U);
  EXPECT_EQ(errors[0], "Среднее число keypoints ниже порога.");
  EXPECT_EQ(errors[1], "Среднее покрытие feature-сетки ниже порога.");
  EXPECT_EQ(errors[2], "Средняя резкость кадра ниже порога.");
  EXPECT_EQ(errors[3], "Средняя яркость кадра ниже порога.");
}

TEST(FeatureDiagnostics, RejectsInvalidThresholds)
{
  yoga_cam_sub::FeatureMonitorSummary summary;
  summary.frames = 1U;
  summary.average_keypoints = 200.0;
  summary.average_grid_coverage_ratio = 0.8;
  summary.average_blur_score = 200.0;
  summary.average_brightness_mean = 90.0;

  yoga_cam_sub::FeatureMonitorThresholds thresholds;
  thresholds.min_average_keypoints = 150;
  thresholds.min_average_grid_coverage_ratio = 1.5;
  thresholds.min_average_blur_score = 50.0;
  thresholds.min_average_brightness_mean = 20.0;

  EXPECT_THROW(yoga_cam_sub::validate_feature_summary(summary, thresholds), std::invalid_argument);
}

}  // namespace
