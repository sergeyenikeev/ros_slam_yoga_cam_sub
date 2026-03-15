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
        DeclareLaunchArgument('publisher_max_frames', default_value='120'),
        DeclareLaunchArgument('required_frames', default_value='20'),
        DeclareLaunchArgument('max_runtime_seconds', default_value='20'),
        DeclareLaunchArgument('log_every_n_frames', default_value='10'),
        DeclareLaunchArgument('max_features', default_value='500'),
        DeclareLaunchArgument('grid_rows', default_value='4'),
        DeclareLaunchArgument('grid_cols', default_value='4'),
        DeclareLaunchArgument('min_average_keypoints', default_value='150'),
        DeclareLaunchArgument('min_average_grid_coverage_ratio', default_value='0.35'),
        DeclareLaunchArgument('min_average_blur_score', default_value='80.0'),
        DeclareLaunchArgument('min_average_brightness_mean', default_value='25.0'),
        # Launch объединяет живой publisher и feature-мониторинг
        # потока в один воспроизводимый сценарий.
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
            executable='camera_feature_monitor',
            name='camera_feature_monitor',
            output='screen',
            parameters=[
                {
                    'image_topic': LaunchConfiguration('image_topic'),
                    'required_frames': LaunchConfiguration('required_frames'),
                    'max_runtime_seconds': LaunchConfiguration('max_runtime_seconds'),
                    'log_every_n_frames': LaunchConfiguration('log_every_n_frames'),
                    'max_features': LaunchConfiguration('max_features'),
                    'grid_rows': LaunchConfiguration('grid_rows'),
                    'grid_cols': LaunchConfiguration('grid_cols'),
                    'min_average_keypoints': LaunchConfiguration('min_average_keypoints'),
                    'min_average_grid_coverage_ratio': LaunchConfiguration(
                        'min_average_grid_coverage_ratio'),
                    'min_average_blur_score': LaunchConfiguration('min_average_blur_score'),
                    'min_average_brightness_mean': LaunchConfiguration(
                        'min_average_brightness_mean'),
                },
            ],
        ),
    ])
