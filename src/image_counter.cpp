#include <memory>
#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/image.hpp"

class ImageCounter : public rclcpp::Node
{
public:
  ImageCounter() : Node("image_counter"), count_(0)
  {
    sub_ = this->create_subscription<sensor_msgs::msg::Image>(
      "/image",
      10,
      [this](const sensor_msgs::msg::Image::SharedPtr msg)
      {
        ++count_;
        RCLCPP_INFO(
          this->get_logger(),
          "frame=%zu width=%u height=%u encoding=%s step=%u",
          count_,
          msg->width,
          msg->height,
          msg->encoding.c_str(),
          msg->step);
      });
  }

private:
  size_t count_;
  rclcpp::Subscription<sensor_msgs::msg::Image>::SharedPtr sub_;
};

int main(int argc, char ** argv)
{
  rclcpp::init(argc, argv);
  rclcpp::spin(std::make_shared<ImageCounter>());
  rclcpp::shutdown();
  return 0;
}