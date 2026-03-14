# SLAM preflight-проверка

`camera_slam_preflight` — вспомогательный ROS 2 узел, который проверяет, что поток камеры уже достаточно стабилен для следующего monocular SLAM-шага.

## Что именно проверяется

Узел подписывается на:

- `/camera/image_raw`
- `/camera/camera_info`

И проверяет:

- приходят ли оба топика за ограниченное время;
- совпадают ли `width`, `height` и `frame_id` между `Image` и `CameraInfo`;
- не пустой ли `encoding` у изображения;
- не повреждены ли матрицы `K` и `P` в `CameraInfo`;
- какой фактический FPS наблюдается на потоке;
- похожа ли калибровка на шаблонную, а не на реальную.

## Когда это полезно

Preflight стоит запускать в трёх случаях:

1. после первой сборки и запуска камеры;
2. после импорта новой калибровки;
3. перед подключением внешнего SLAM-пакета.

## Быстрый запуск

Если `camera_publisher` уже работает отдельно, можно проверить только анализатор:

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_slam_preflight --ros-args -p image_topic:=/camera/image_raw -p camera_info_topic:=/camera/camera_info
```

Для автоматического сценария с запуском publisher используйте:

```powershell
.\scripts\run_slam_preflight.ps1 calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

## Основные параметры

- `image_topic` — топик изображений;
- `camera_info_topic` — топик `CameraInfo`;
- `expected_frame_id` — ожидаемый `frame_id` для обоих сообщений;
- `required_frames` — сколько кадров нужно собрать до успешного завершения;
- `max_runtime_seconds` — сколько максимум ждать поток;
- `min_fps` — минимально допустимый средний FPS;
- `log_every_n_frames` — как часто печатать промежуточные сообщения.

## Автоматическая smoke-проверка

```powershell
.\scripts\slam_preflight_smoke_test.ps1
```

Скрипт:

- поднимает `camera_publisher` в фоне;
- при наличии использует `config/camera_calibration.local.yaml`;
- запускает `camera_slam_preflight`;
- завершает проверку с ненулевым кодом, если поток не прошёл критерии.

## Интерпретация результата

Успешный прогон заканчивается сообщением вида:

```text
SLAM preflight завершён успешно. Поток готов к следующему этапу интеграции.
```

И summary-блоком с метриками:

- `images` — сколько кадров реально проанализировано;
- `camera_infos` — сколько сообщений `CameraInfo` пришло;
- `average_fps` — фактический средний FPS;
- `mean_period_ms`, `min_period_ms`, `max_period_ms` — интервалы между кадрами;
- `stddev_period_ms` — разброс интервалов, полезный как индикатор джиттера.

## Типичные причины провала

- камера не открылась, поэтому кадры не публикуются;
- publisher и preflight слушают разные топики;
- `frame_id` в `Image` и `CameraInfo` различается;
- `CameraInfo` ещё шаблонный или повреждён;
- реальный FPS оказался ниже порога `min_fps`.

## Что делать после успешного preflight

1. сохранить рабочие параметры разрешения и FPS;
2. убедиться, что используется реальная калибровка, а не шаблон;
3. подключать следующий SLAM launch уже к тем же `/camera/image_raw` и `/camera/camera_info`.
