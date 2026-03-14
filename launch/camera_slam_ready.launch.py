import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration


def generate_launch_description():
    package_share = get_package_share_directory('yoga_cam_sub')
    camera_launch = os.path.join(package_share, 'launch', 'camera_publisher.launch.py')
    tf_launch = os.path.join(package_share, 'launch', 'static_camera_tf.launch.py')

    return LaunchDescription([
        DeclareLaunchArgument(
            'params_file',
            default_value=os.path.join(
                package_share, 'config', 'camera_publisher.params.yaml')),
        DeclareLaunchArgument('device_index', default_value='0'),
        DeclareLaunchArgument('width', default_value='640'),
        DeclareLaunchArgument('height', default_value='360'),
        DeclareLaunchArgument('fps', default_value='30.0'),
        DeclareLaunchArgument('frame_id', default_value='camera_optical_frame'),
        DeclareLaunchArgument('use_msmf', default_value='true'),
        DeclareLaunchArgument('max_frames', default_value='0'),
        DeclareLaunchArgument('calibration_file', default_value=''),
        DeclareLaunchArgument('parent_frame', default_value='camera_link'),
        DeclareLaunchArgument('child_frame', default_value='camera_optical_frame'),
        DeclareLaunchArgument('x', default_value='0.0'),
        DeclareLaunchArgument('y', default_value='0.0'),
        DeclareLaunchArgument('z', default_value='0.0'),
        DeclareLaunchArgument('roll', default_value='-1.57079632679'),
        DeclareLaunchArgument('pitch', default_value='0.0'),
        DeclareLaunchArgument('yaw', default_value='-1.57079632679'),
        # Переиспользуем уже проверенный launch publisher, чтобы не дублировать его конфигурацию.
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(camera_launch),
            launch_arguments={
                'params_file': LaunchConfiguration('params_file'),
                'device_index': LaunchConfiguration('device_index'),
                'width': LaunchConfiguration('width'),
                'height': LaunchConfiguration('height'),
                'fps': LaunchConfiguration('fps'),
                'frame_id': LaunchConfiguration('frame_id'),
                'use_msmf': LaunchConfiguration('use_msmf'),
                'calibration_file': LaunchConfiguration('calibration_file'),
                'max_frames': LaunchConfiguration('max_frames'),
            }.items(),
        ),
        IncludeLaunchDescription(
            PythonLaunchDescriptionSource(tf_launch),
            launch_arguments={
                'parent_frame': LaunchConfiguration('parent_frame'),
                'child_frame': LaunchConfiguration('child_frame'),
                'x': LaunchConfiguration('x'),
                'y': LaunchConfiguration('y'),
                'z': LaunchConfiguration('z'),
                'roll': LaunchConfiguration('roll'),
                'pitch': LaunchConfiguration('pitch'),
                'yaw': LaunchConfiguration('yaw'),
            }.items(),
        ),
    ])
