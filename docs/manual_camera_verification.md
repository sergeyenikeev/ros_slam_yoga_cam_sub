# Ручная проверка камеры

Эти шаги нужны, если автоматическая среда не имеет доступа к физической камере, но пакет уже собран.

## 1. Сборка

```powershell
.\scripts\build_workspace.ps1
```

Если хотите сначала прогнать все автоматические проверки:

```powershell
.\scripts\full_validation.ps1
```

## 2. Запуск publisher

```powershell
.\scripts\run_camera_publisher.ps1 --ros-args -p device_index:=0 -p width:=640 -p height:=360 -p fps:=30.0
```

Ожидаемые признаки успеха в логах:

- узел сообщает, что параметры загружены;
- появляется сообщение `Пробуем открыть камеру`;
- появляется сообщение `Камера открыта`;
- затем появляются сообщения `Опубликован кадр` и `Опубликован CameraInfo`.

## 3. Проверка списка топиков

В отдельном окне:

```cmd
scripts\run_in_ros_env.cmd ros2 topic list
```

Ожидается наличие:

- `/camera/image_raw`
- `/camera/camera_info`

## 4. Проверка одного сообщения `Image`

```cmd
scripts\run_in_ros_env.cmd ros2 topic echo --once /camera/image_raw
```

Если кадры идут, команда вернёт одно сообщение `sensor_msgs/msg/Image`.

## 5. Проверка одного сообщения `CameraInfo`

```cmd
scripts\run_in_ros_env.cmd ros2 topic echo --once /camera/camera_info
```

Ожидается сообщение `sensor_msgs/msg/CameraInfo` с корректными `width`, `height`, `distortion_model`, `k`, `r`, `p`.

## 6. Проверка subscriber

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub image_counter --ros-args -p image_topic:=/camera/image_raw
```

Ожидается поток логов вида:

```text
Получен кадр #1: frame_id=... width=640 height=360 encoding=bgr8 step=...
```

## 7. Проверка launch-файла

```cmd
scripts\run_in_ros_env.cmd ros2 launch yoga_cam_sub camera_pipeline.launch.py
```

Если камера доступна, одновременно должны работать `camera_publisher` и `image_counter`.

## 8. Если камера не открывается

Попробуйте fallback на `CAP_ANY`:

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args -p use_msmf:=false
```

Также можно поменять индекс камеры:

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args -p device_index:=1
```
