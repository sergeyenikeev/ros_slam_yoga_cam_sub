#include <stdexcept>
#include <vector>

#include <gtest/gtest.h>
#include <opencv2/core/mat.hpp>
#include <opencv2/core/types.hpp>

#include "rclcpp/time.hpp"
#include "yoga_cam_sub/camera_utils.hpp"

namespace
{

TEST(CameraParameters, RejectsInvalidValues)
{
  yoga_cam_sub::CameraParameters parameters;
  parameters.device_index = -1;
  parameters.width = 0;
  parameters.height = -10;
  parameters.fps = 0.0;
  parameters.frame_id.clear();
  parameters.image_topic.clear();
  parameters.camera_info_topic.clear();
  parameters.max_frames = -1;

  const auto errors = yoga_cam_sub::validate_camera_parameters(parameters);
  EXPECT_EQ(errors.size(), 8U);
}

TEST(CameraFrame, ConvertsMonoToBgr)
{
  cv::Mat mono(2, 2, CV_8UC1, cv::Scalar(7));
  cv::Mat converted = yoga_cam_sub::prepare_frame_for_publish(mono);

  ASSERT_EQ(converted.type(), CV_8UC3);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[0], 7);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[1], 7);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[2], 7);
}

TEST(CameraFrame, RejectsEmptyFrame)
{
  const cv::Mat empty;
  EXPECT_THROW(yoga_cam_sub::prepare_frame_for_publish(empty), std::invalid_argument);
  EXPECT_THROW(
    yoga_cam_sub::build_image_message(empty, "camera", rclcpp::Time(1, 0, RCL_SYSTEM_TIME)),
    std::invalid_argument);
}

TEST(CameraFrame, BuildsImageMessageForContinuousFrame)
{
  cv::Mat frame(2, 2, CV_8UC3);
  frame.at<cv::Vec3b>(0, 0) = cv::Vec3b(1, 2, 3);
  frame.at<cv::Vec3b>(0, 1) = cv::Vec3b(4, 5, 6);
  frame.at<cv::Vec3b>(1, 0) = cv::Vec3b(7, 8, 9);
  frame.at<cv::Vec3b>(1, 1) = cv::Vec3b(10, 11, 12);

  const auto message = yoga_cam_sub::build_image_message(
    frame,
    "camera_frame",
    rclcpp::Time(123, 456, RCL_SYSTEM_TIME));

  EXPECT_EQ(message.header.frame_id, "camera_frame");
  EXPECT_EQ(message.height, 2U);
  EXPECT_EQ(message.width, 2U);
  EXPECT_EQ(message.encoding, "bgr8");
  EXPECT_EQ(message.step, 6U);
  ASSERT_EQ(message.data.size(), 12U);
  EXPECT_EQ(message.data[0], 1U);
  EXPECT_EQ(message.data[11], 12U);
}

TEST(CameraFrame, BuildsImageMessageForNonContinuousFrame)
{
  cv::Mat base(2, 4, CV_8UC3, cv::Scalar(0, 0, 0));
  base.at<cv::Vec3b>(0, 1) = cv::Vec3b(10, 11, 12);
  base.at<cv::Vec3b>(0, 2) = cv::Vec3b(13, 14, 15);
  base.at<cv::Vec3b>(1, 1) = cv::Vec3b(20, 21, 22);
  base.at<cv::Vec3b>(1, 2) = cv::Vec3b(23, 24, 25);

  const cv::Mat roi = base(cv::Rect(1, 0, 2, 2));
  ASSERT_FALSE(roi.isContinuous());

  const auto message = yoga_cam_sub::build_image_message(
    roi,
    "roi_frame",
    rclcpp::Time(42, 0, RCL_SYSTEM_TIME));

  EXPECT_EQ(message.width, 2U);
  EXPECT_EQ(message.height, 2U);
  EXPECT_EQ(message.step, 6U);
  ASSERT_EQ(message.data.size(), 12U);
  EXPECT_EQ(message.data[0], 10U);
  EXPECT_EQ(message.data[5], 15U);
  EXPECT_EQ(message.data[6], 20U);
  EXPECT_EQ(message.data[11], 25U);
}

TEST(CameraCalibration, CreatesDefaultCalibrationFromImageSize)
{
  const auto calibration = yoga_cam_sub::make_default_calibration(cv::Size(640, 360));

  EXPECT_EQ(calibration.distortion_model, "plumb_bob");
  EXPECT_EQ(calibration.d.size(), 5U);
  EXPECT_DOUBLE_EQ(calibration.k[0], 640.0);
  EXPECT_DOUBLE_EQ(calibration.k[4], 360.0);
  EXPECT_DOUBLE_EQ(calibration.k[2], 319.5);
  EXPECT_DOUBLE_EQ(calibration.k[5], 179.5);
  EXPECT_DOUBLE_EQ(calibration.p[10], 1.0);
}

TEST(CameraCalibration, RejectsWrongMatrixSizes)
{
  EXPECT_THROW(
    yoga_cam_sub::merge_calibration_overrides(
      cv::Size(640, 360),
      "plumb_bob",
      std::vector<double>{0.0, 0.0, 0.0, 0.0, 0.0},
      std::vector<double>{1.0, 2.0},
      std::vector<double>{},
      std::vector<double>{}),
    std::invalid_argument);
}

TEST(CameraCalibration, BuildsCameraInfoMessage)
{
  const auto calibration = yoga_cam_sub::merge_calibration_overrides(
    cv::Size(640, 360),
    "equidistant",
    std::vector<double>{0.1, 0.2, 0.3, 0.4},
    std::vector<double>{1.0, 0.0, 2.0, 0.0, 3.0, 4.0, 0.0, 0.0, 1.0},
    std::vector<double>{1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0},
    std::vector<double>{1.0, 0.0, 2.0, 0.0, 0.0, 3.0, 4.0, 0.0, 0.0, 0.0, 1.0, 0.0});

  const auto message = yoga_cam_sub::build_camera_info_message(
    cv::Size(640, 360),
    "camera_frame",
    rclcpp::Time(0, 0, RCL_ROS_TIME),
    calibration);

  EXPECT_EQ(message.width, 640U);
  EXPECT_EQ(message.height, 360U);
  EXPECT_EQ(message.distortion_model, "equidistant");
  EXPECT_EQ(message.d.size(), 4U);
  EXPECT_DOUBLE_EQ(message.k[2], 2.0);
  EXPECT_DOUBLE_EQ(message.p[6], 4.0);
}

}  // namespace
