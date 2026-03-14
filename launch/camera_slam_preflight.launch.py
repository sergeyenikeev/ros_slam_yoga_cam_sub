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
        DeclareLaunchArgument('frame_id', default_value='camera_optical_frame'),
        DeclareLaunchArgument('image_topic', default_value='/camera/image_raw'),
        DeclareLaunchArgument('camera_info_topic', default_value='/camera/camera_info'),
        DeclareLaunchArgument('use_msmf', default_value='true'),
        DeclareLaunchArgument('calibration_file', default_value=''),
        DeclareLaunchArgument('publisher_max_frames', default_value='90'),
        DeclareLaunchArgument('required_frames', default_value='30'),
        DeclareLaunchArgument('max_runtime_seconds', default_value='20'),
        DeclareLaunchArgument('min_fps', default_value='5.0'),
        DeclareLaunchArgument('log_every_n_frames', default_value='10'),
        # Launch объединяет источник камеры и preflight-проверку в один воспроизводимый сценарий.
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
                    'frame_id': LaunchConfiguration('frame_id'),
                    'image_topic': LaunchConfiguration('image_topic'),
                    'camera_info_topic': LaunchConfiguration('camera_info_topic'),
                    'use_msmf': LaunchConfiguration('use_msmf'),
                    'calibration_file': LaunchConfiguration('calibration_file'),
                    'max_frames': LaunchConfiguration('publisher_max_frames'),
                },
            ],
        ),
        Node(
            package='yoga_cam_sub',
            executable='camera_slam_preflight',
            name='camera_slam_preflight',
            output='screen',
            parameters=[
                {
                    'image_topic': LaunchConfiguration('image_topic'),
                    'camera_info_topic': LaunchConfiguration('camera_info_topic'),
                    'expected_frame_id': LaunchConfiguration('frame_id'),
                    'required_frames': LaunchConfiguration('required_frames'),
                    'max_runtime_seconds': LaunchConfiguration('max_runtime_seconds'),
                    'min_fps': LaunchConfiguration('min_fps'),
                    'log_every_n_frames': LaunchConfiguration('log_every_n_frames'),
                },
            ],
        ),
    ])
