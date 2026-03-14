cmake_minimum_required(VERSION 3.16)
project(yoga_cam_sub LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  add_compile_options(/W4 /EHsc /utf-8)
else()
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

if(NOT OpenCV_DIR AND DEFINED ENV{OpenCV_DIR})
  set(OpenCV_DIR "$ENV{OpenCV_DIR}")
endif()

if(OpenCV_DIR AND EXISTS "${OpenCV_DIR}/x64/vc17/lib/OpenCVConfig.cmake")
  set(OpenCV_DIR "${OpenCV_DIR}/x64/vc17/lib")
elseif(OpenCV_DIR AND EXISTS "${OpenCV_DIR}/x64/vc16/lib/OpenCVConfig.cmake")
  set(OpenCV_DIR "${OpenCV_DIR}/x64/vc16/lib")
elseif(OpenCV_DIR AND EXISTS "${OpenCV_DIR}/x64/vc15/lib/OpenCVConfig.cmake")
  set(OpenCV_DIR "${OpenCV_DIR}/x64/vc15/lib")
endif()

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(sensor_msgs REQUIRED)
find_package(OpenCV REQUIRED COMPONENTS core imgproc videoio)

add_library(camera_utils src/camera_utils.cpp)
target_include_directories(camera_utils
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>)
ament_target_dependencies(camera_utils rclcpp sensor_msgs)
target_link_libraries(camera_utils ${OpenCV_LIBS})

add_executable(image_counter src/image_counter.cpp)
ament_target_dependencies(image_counter rclcpp sensor_msgs)

add_executable(camera_publisher src/camera_publisher.cpp)
target_link_libraries(camera_publisher camera_utils)
ament_target_dependencies(camera_publisher rclcpp sensor_msgs)

install(
  TARGETS camera_utils image_counter camera_publisher
  EXPORT export_${PROJECT_NAME}
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION lib/${PROJECT_NAME}
)

install(DIRECTORY include/ DESTINATION include)
install(DIRECTORY launch config docs scripts DESTINATION share/${PROJECT_NAME})

ament_export_include_directories(include)
ament_export_targets(export_${PROJECT_NAME})
ament_export_dependencies(rclcpp sensor_msgs)

if(BUILD_TESTING)
  find_package(ament_cmake_gtest REQUIRED)
  find_package(ament_lint_auto REQUIRED)

  set(ament_cmake_copyright_FOUND TRUE)
  set(ament_cmake_cpplint_FOUND TRUE)
  set(ament_cmake_uncrustify_FOUND TRUE)
  ament_lint_auto_find_test_dependencies()

  ament_add_gtest(test_camera_utils test/test_camera_utils.cpp)
  if(TARGET test_camera_utils)
    target_link_libraries(test_camera_utils camera_utils)
  endif()
endif()

ament_package()
