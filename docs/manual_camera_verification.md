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

## 8. Проверка статического TF

В отдельном окне:

```cmd
scripts\run_in_ros_env.cmd ros2 launch yoga_cam_sub static_camera_tf.launch.py
```

И затем:

```cmd
scripts\run_in_ros_env.cmd ros2 topic echo --once /tf_static
```

Ожидается transform с `frame_id: camera_link` и `child_frame_id: camera_optical_frame`.

## 9. Подготовка к калибровке

Сначала можно проверить доступность GUI-калибратора и готовую команду запуска:

```powershell
.\scripts\run_camera_calibration.ps1 -CheckOnly
```

Если инструмент установлен, тот же скрипт можно запустить без `-CheckOnly`.

## 10. Проверка реальной калибровки

Если у вас уже есть `ost.yaml` или другой стандартный YAML от `camera_calibration`, импортируйте его:

```powershell
.\scripts\import_camera_calibration.ps1 -SourceFile C:\путь\к\ost.yaml
```

После этого можно запустить publisher уже с реальной калибровкой:

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args -p calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

В логах должны появиться сообщения `Загружен calibration_file` и `Подготовлен CameraInfo ... Значения калибровки загружены из calibration_file`.

## 11. Preflight-проверка потока перед SLAM

После импорта калибровки полезно проверить сам поток:

```powershell
.\scripts\run_slam_preflight.ps1 calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

Ожидаемые признаки успеха:

- приходит первый `CameraInfo`;
- в логах появляются строки `Preflight получил кадр #...`;
- в summary виден `average_fps`;
- прогон завершается сообщением `SLAM preflight завершён успешно`.

## 12. Запись bag-датасета для повторной проверки

Если поток уже стабилен, можно записать короткий rosbag:

```powershell
.\scripts\run_dataset_record.ps1 -DurationSeconds 5
```

Скрипт по умолчанию пишет bag через `sqlite3`, чтобы затем тот же датасет можно было сразу воспроизвести через `ros2 bag play` без проблем с порядком сообщений.

После записи можно воспроизвести датасет уже без камеры:

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunPreflight
```

Так удобно подтверждать, что будущий SLAM-модуль стабильно работает на одном и том же входе.

## 13. Если камера не открывается

Попробуйте fallback на `CAP_ANY`:

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args -p use_msmf:=false
```

Также можно поменять индекс камеры:

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args -p device_index:=1
```
