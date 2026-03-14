#include <chrono>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

#include <gtest/gtest.h>
#include <opencv2/core/mat.hpp>
#include <opencv2/core/types.hpp>
#include <opencv2/videoio.hpp>

#include "rclcpp/time.hpp"
#include "yoga_cam_sub/camera_utils.hpp"

namespace
{

class TemporaryCalibrationFile
{
public:
  explicit TemporaryCalibrationFile(const std::string & contents)
  {
    const auto unique_id = std::to_string(
      std::chrono::steady_clock::now().time_since_epoch().count());
    path_ = std::filesystem::temp_directory_path() /
      ("yoga_cam_sub_calibration_" + unique_id + ".yaml");

    std::ofstream stream(path_);
    stream << contents;
  }

  ~TemporaryCalibrationFile()
  {
    std::error_code error;
    std::filesystem::remove(path_, error);
  }

  const std::filesystem::path & path() const
  {
    return path_;
  }

private:
  std::filesystem::path path_;
};

std::string make_sample_calibration_yaml()
{
  return R"(%YAML:1.0
---
image_width: 640
image_height: 360
camera_name: yoga_test_camera
camera_matrix:
  rows: 3
  cols: 3
  data: [ 640.0, 0.0, 319.5, 0.0, 360.0, 179.5, 0.0, 0.0, 1.0 ]
distortion_model: plumb_bob
distortion_coefficients:
  rows: 1
  cols: 5
  data: [ 0.1, 0.2, 0.3, 0.4, 0.5 ]
rectification_matrix:
  rows: 3
  cols: 3
  data: [ 1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0 ]
projection_matrix:
  rows: 3
  cols: 4
  data: [ 640.0, 0.0, 319.5, 0.0, 0.0, 360.0, 179.5, 0.0, 0.0, 0.0, 1.0, 0.0 ]
)";
}

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

TEST(CameraFrame, ConvertsBgraToBgr)
{
  cv::Mat bgra(1, 1, CV_8UC4, cv::Scalar(3, 4, 5, 255));
  cv::Mat converted = yoga_cam_sub::prepare_frame_for_publish(bgra);

  ASSERT_EQ(converted.type(), CV_8UC3);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[0], 3);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[1], 4);
  EXPECT_EQ(converted.at<cv::Vec3b>(0, 0)[2], 5);
}

TEST(CameraFrame, RejectsUnsupportedFrameType)
{
  cv::Mat unsupported(1, 1, CV_16UC1, cv::Scalar(1));
  EXPECT_THROW(yoga_cam_sub::prepare_frame_for_publish(unsupported), std::invalid_argument);
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

  // ROI специально оставляем неcontinuous, чтобы проверить построчное копирование.
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

  EXPECT_EQ(calibration.camera_name, "camera");
  EXPECT_EQ(calibration.calibration_image_size.width, 640);
  EXPECT_EQ(calibration.calibration_image_size.height, 360);
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

TEST(CameraCalibration, RejectsInvalidCameraInfoCalibration)
{
  yoga_cam_sub::CameraCalibration calibration = yoga_cam_sub::make_default_calibration(cv::Size(640, 360));
  calibration.p[10] = 0.0;

  EXPECT_THROW(
    yoga_cam_sub::build_camera_info_message(
      cv::Size(640, 360),
      "camera_frame",
      rclcpp::Time(0, 0, RCL_ROS_TIME),
      calibration),
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

TEST(CameraCalibration, LoadsCalibrationFile)
{
  const TemporaryCalibrationFile calibration_file(make_sample_calibration_yaml());
  const auto calibration = yoga_cam_sub::load_camera_calibration_file(calibration_file.path().string());

  EXPECT_EQ(calibration.camera_name, "yoga_test_camera");
  EXPECT_EQ(calibration.calibration_image_size.width, 640);
  EXPECT_EQ(calibration.calibration_image_size.height, 360);
  EXPECT_EQ(calibration.distortion_model, "plumb_bob");
  EXPECT_EQ(calibration.d.size(), 5U);
  EXPECT_DOUBLE_EQ(calibration.k[0], 640.0);
  EXPECT_DOUBLE_EQ(calibration.k[4], 360.0);
}

TEST(CameraCalibration, RejectsMissingCalibrationFile)
{
  EXPECT_THROW(
    yoga_cam_sub::load_camera_calibration_file(
      (std::filesystem::temp_directory_path() / "absent_yoga_cam_sub_calibration.yaml").string()),
    std::invalid_argument);
}

TEST(CameraCalibration, RejectsCalibrationFileWithoutRequiredField)
{
  const TemporaryCalibrationFile calibration_file(R"(%YAML:1.0
---
image_width: 640
image_height: 360
camera_name: broken_camera
distortion_model: plumb_bob
)"
  );

  EXPECT_THROW(
    yoga_cam_sub::load_camera_calibration_file(calibration_file.path().string()),
    std::invalid_argument);
}

TEST(CameraCalibration, ScalesCalibrationToNewResolution)
{
  const TemporaryCalibrationFile calibration_file(make_sample_calibration_yaml());
  const auto source = yoga_cam_sub::load_camera_calibration_file(calibration_file.path().string());
  const auto scaled = yoga_cam_sub::scale_camera_calibration(source, cv::Size(1280, 720));

  EXPECT_EQ(scaled.calibration_image_size.width, 1280);
  EXPECT_EQ(scaled.calibration_image_size.height, 720);
  EXPECT_DOUBLE_EQ(scaled.k[0], 1280.0);
  EXPECT_DOUBLE_EQ(scaled.k[4], 720.0);
  EXPECT_DOUBLE_EQ(scaled.k[2], 639.0);
  EXPECT_DOUBLE_EQ(scaled.k[5], 359.0);
  EXPECT_DOUBLE_EQ(scaled.p[0], 1280.0);
  EXPECT_DOUBLE_EQ(scaled.p[5], 720.0);
}

TEST(CameraCalibration, RejectsScalingForInvalidTargetSize)
{
  const auto calibration = yoga_cam_sub::make_default_calibration(cv::Size(640, 360));
  EXPECT_THROW(
    yoga_cam_sub::scale_camera_calibration(calibration, cv::Size(0, 720)),
    std::invalid_argument);
}

TEST(CameraCalibration, DescribesKnownBackend)
{
  EXPECT_EQ(yoga_cam_sub::describe_video_backend(cv::CAP_MSMF), "CAP_MSMF");
}

TEST(CameraBackends, BuildsPreferredPriorityForMsmf)
{
  const auto backends = yoga_cam_sub::build_video_backend_priority(true);

  ASSERT_EQ(backends.size(), 2U);
  EXPECT_EQ(backends[0], cv::CAP_MSMF);
  EXPECT_EQ(backends[1], cv::CAP_ANY);
}

TEST(CameraBackends, BuildsRecoveryPriorityWithFallbackFirst)
{
  const auto backends = yoga_cam_sub::build_recovery_backend_priority(
    std::vector<int>{cv::CAP_MSMF, cv::CAP_ANY},
    cv::CAP_MSMF);

  ASSERT_EQ(backends.size(), 2U);
  EXPECT_EQ(backends[0], cv::CAP_ANY);
  EXPECT_EQ(backends[1], cv::CAP_MSMF);
}

TEST(CameraBackends, DeduplicatesRecoveryPriority)
{
  const auto backends = yoga_cam_sub::build_recovery_backend_priority(
    std::vector<int>{cv::CAP_ANY, cv::CAP_ANY},
    cv::CAP_ANY);

  ASSERT_EQ(backends.size(), 1U);
  EXPECT_EQ(backends[0], cv::CAP_ANY);
}

}  // namespace
