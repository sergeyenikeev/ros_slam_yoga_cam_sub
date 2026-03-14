#include <memory>
// Базовые зависимости ROS 2: ядро rclcpp для работы с узлами и сообщение изображения.
#include "rclcpp/rclcpp.hpp"
#include "sensor_msgs/msg/image.hpp"

class ImageCounter : public rclcpp::Node
{
public:
  ImageCounter() : Node("image_counter"), count_(0)
  {
    // Создаем подписку на топик с изображениями. Буфер 10 сообщений позволяет
    // аккумулировать кадры, если потребление немного запаздывает.
    sub_ = this->create_subscription<sensor_msgs::msg::Image>(
      "/image",
      10,
      [this](const sensor_msgs::msg::Image::SharedPtr msg)
      {
        // На каждый принятый кадр увеличиваем счетчик.
        ++count_;
        // Выводим диагностику: номер кадра плюс параметры изображения, чтобы
        // можно было следить за разрешением и форматом потока.
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
  // Инициализация ядра ROS 2 перед созданием узлов и подписок.
  rclcpp::init(argc, argv);
  // Запускаем узел, чтобы он обрабатывал все сообщения подписки, пока не остановлен.
  rclcpp::spin(std::make_shared<ImageCounter>());
  // Очищаем ресурсы rclcpp и завершаем работу.
  rclcpp::shutdown();
  return 0;
}
