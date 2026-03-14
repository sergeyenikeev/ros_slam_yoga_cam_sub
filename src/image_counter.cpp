#include <cstdint>
#include <memory>
#include <stdexcept>
#include <string>

#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/image.hpp"

class ImageCounter : public rclcpp::Node
{
public:
  ImageCounter()
  : Node("image_counter"), count_(0)
  {
    image_topic_ = this->declare_parameter<std::string>("image_topic", "/camera/image_raw");
    max_frames_ = static_cast<int>(this->declare_parameter<std::int64_t>("max_frames", 0));

    if (image_topic_.empty()) {
      throw std::invalid_argument("Параметр image_topic не должен быть пустым.");
    }
    if (max_frames_ < 0) {
      throw std::invalid_argument("Параметр max_frames не может быть отрицательным.");
    }

    const auto qos = rclcpp::SensorDataQoS();
    sub_ = this->create_subscription<sensor_msgs::msg::Image>(
      image_topic_,
      qos,
      [this](const sensor_msgs::msg::Image::SharedPtr msg)
      {
        ++count_;
        RCLCPP_INFO(
          this->get_logger(),
          "Получен кадр #%zu: frame_id=%s width=%u height=%u encoding=%s step=%u",
          count_,
          msg->header.frame_id.c_str(),
          msg->width,
          msg->height,
          msg->encoding.c_str(),
          msg->step);

        if (max_frames_ > 0 && static_cast<int>(count_) >= max_frames_) {
          RCLCPP_INFO(
            this->get_logger(),
            "Достигнут лимит max_frames=%d. Узел завершает работу.",
            max_frames_);
          rclcpp::shutdown();
        }
      });

    RCLCPP_INFO(
      this->get_logger(),
      "Узел image_counter запущен. Подписка на топик '%s', max_frames=%d.",
      image_topic_.c_str(),
      max_frames_);
  }

private:
  std::size_t count_;
  int max_frames_;
  std::string image_topic_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr sub_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);

  try {
    rclcpp::spin(std::make_shared<ImageCounter>());
  } catch (const std::exception & error) {
    RCLCPP_FATAL(
      rclcpp::get_logger("image_counter"),
      "Узел image_counter завершился с ошибкой: %s",
      error.what());
    rclcpp::shutdown();
    return 1;
  }

  rclcpp::shutdown();
  return 0;
}
