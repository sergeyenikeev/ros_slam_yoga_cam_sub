from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    return LaunchDescription([
        DeclareLaunchArgument('parent_frame', default_value='camera_link'),
        DeclareLaunchArgument('child_frame', default_value='camera_optical_frame'),
        DeclareLaunchArgument('x', default_value='0.0'),
        DeclareLaunchArgument('y', default_value='0.0'),
        DeclareLaunchArgument('z', default_value='0.0'),
        # Базовое преобразование соответствует стандартной ROS-конвенции optical frame.
        DeclareLaunchArgument('roll', default_value='-1.57079632679'),
        DeclareLaunchArgument('pitch', default_value='0.0'),
        DeclareLaunchArgument('yaw', default_value='-1.57079632679'),
        Node(
            package='tf2_ros',
            executable='static_transform_publisher',
            name='camera_optical_static_tf',
            output='screen',
            arguments=[
                LaunchConfiguration('x'),
                LaunchConfiguration('y'),
                LaunchConfiguration('z'),
                LaunchConfiguration('roll'),
                LaunchConfiguration('pitch'),
                LaunchConfiguration('yaw'),
                LaunchConfiguration('parent_frame'),
                LaunchConfiguration('child_frame'),
            ],
        ),
    ])
