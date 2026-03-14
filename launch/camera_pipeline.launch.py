import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description():
    package_share = get_package_share_directory('yoga_cam_sub')
    default_params = os.path.join(package_share, 'config', 'camera_publisher.params.yaml')

    return LaunchDescription([
        DeclareLaunchArgument('params_file', default_value=default_params),
        DeclareLaunchArgument('device_index', default_value='0'),
        DeclareLaunchArgument('width', default_value='640'),
        DeclareLaunchArgument('height', default_value='360'),
        DeclareLaunchArgument('fps', default_value='30.0'),
        DeclareLaunchArgument('use_msmf', default_value='true'),
        DeclareLaunchArgument('frame_id', default_value='camera_optical_frame'),
        DeclareLaunchArgument('image_topic', default_value='/camera/image_raw'),
        DeclareLaunchArgument('camera_info_topic', default_value='/camera/camera_info'),
        DeclareLaunchArgument('publisher_max_frames', default_value='0'),
        DeclareLaunchArgument('counter_max_frames', default_value='0'),
        Node(
            package='yoga_cam_sub',
            executable='camera_publisher',
            name='camera_publisher',
            output='screen',
            parameters=[
                LaunchConfiguration('params_file'),
                {
                    'device_index': LaunchConfiguration('device_index'),
                    'width': LaunchConfiguration('width'),
                    'height': LaunchConfiguration('height'),
                    'fps': LaunchConfiguration('fps'),
                    'use_msmf': LaunchConfiguration('use_msmf'),
                    'frame_id': LaunchConfiguration('frame_id'),
                    'image_topic': LaunchConfiguration('image_topic'),
                    'camera_info_topic': LaunchConfiguration('camera_info_topic'),
                    'max_frames': LaunchConfiguration('publisher_max_frames'),
                },
            ],
        ),
        Node(
            package='yoga_cam_sub',
            executable='image_counter',
            name='image_counter',
            output='screen',
            parameters=[
                LaunchConfiguration('params_file'),
                {
                    'image_topic': LaunchConfiguration('image_topic'),
                    'max_frames': LaunchConfiguration('counter_max_frames'),
                },
            ],
        ),
    ])
