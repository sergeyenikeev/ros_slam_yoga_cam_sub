#include <cstdint>
#include <stdexcept>
#include <vector>

#include <gtest/gtest.h>

#include "sensor_msgs/msg/camera_info.hpp"
#include "sensor_msgs/msg/image.hpp"
#include "yoga_cam_sub/camera_utils.hpp"
#include "yoga_cam_sub/stream_diagnostics.hpp"

namespace
{

sensor_msgs::msg::Image make_image_message(
  uint32_t width,
  uint32_t height,
  const std::string & frame_id,
  const std::string & encoding)
{
  sensor_msgs::msg::Image message;
  message.width = width;
  message.height = height;
  message.header.frame_id = frame_id;
  message.encoding = encoding;
  message.step = width * 3U;
  return message;
}

sensor_msgs::msg::CameraInfo make_camera_info_message(uint32_t width, uint32_t height)
{
  const auto calibration = yoga_cam_sub::make_default_calibration(
    cv::Size(static_cast<int>(width), static_cast<int>(height)));

  sensor_msgs::msg::CameraInfo message;
  message.width = width;
  message.height = height;
  message.header.frame_id = "camera_optical_frame";
  message.distortion_model = calibration.distortion_model;
  message.d = calibration.d;
  std::copy(calibration.k.begin(), calibration.k.end(), message.k.begin());
  std::copy(calibration.r.begin(), calibration.r.end(), message.r.begin());
  std::copy(calibration.p.begin(), calibration.p.end(), message.p.begin());
  return message;
}

TEST(StreamDiagnostics, CalculatesTimingStatistics)
{
  const auto statistics = yoga_cam_sub::calculate_timing_statistics(
    std::vector<std::int64_t>{0, 33'000'000, 66'000'000, 99'000'000});

  EXPECT_EQ(statistics.intervals, 3U);
  EXPECT_NEAR(statistics.average_fps, 30.303, 0.01);
  EXPECT_NEAR(statistics.mean_period_ms, 33.0, 0.001);
  EXPECT_NEAR(statistics.stddev_period_ms, 0.0, 0.001);
}

TEST(StreamDiagnostics, RejectsNonMonotonicTimestamps)
{
  EXPECT_THROW(
    yoga_cam_sub::calculate_timing_statistics(std::vector<std::int64_t>{0, 10, 10}),
    std::invalid_argument);
}

TEST(StreamDiagnostics, ValidatesMatchingImageAndCameraInfo)
{
  const auto image = make_image_message(640U, 360U, "camera_optical_frame", "bgr8");
  const auto camera_info = make_camera_info_message(640U, 360U);

  const auto errors = yoga_cam_sub::validate_image_and_camera_info(image, camera_info);
  EXPECT_TRUE(errors.empty());
}

TEST(StreamDiagnostics, DetectsImageAndCameraInfoMismatch)
{
  const auto image = make_image_message(640U, 360U, "left_camera", "bgr8");
  auto camera_info = make_camera_info_message(640U, 360U);
  camera_info.width = 320U;

  const auto errors = yoga_cam_sub::validate_image_and_camera_info(image, camera_info);
  ASSERT_EQ(errors.size(), 2U);
  EXPECT_EQ(errors[0], "Ширина Image и CameraInfo не совпадает.");
  EXPECT_EQ(errors[1], "frame_id в Image и CameraInfo не совпадает.");
}

TEST(StreamDiagnostics, DetectsTemplateLikeCameraInfo)
{
  const auto camera_info = make_camera_info_message(640U, 360U);
  EXPECT_TRUE(yoga_cam_sub::camera_info_matches_template(camera_info));
}

TEST(StreamDiagnostics, DistinguishesModifiedCalibrationFromTemplate)
{
  auto camera_info = make_camera_info_message(640U, 360U);
  camera_info.d[0] = 0.05;

  EXPECT_FALSE(yoga_cam_sub::camera_info_matches_template(camera_info));
}

}  // namespace
