# Переход к калибровке и monocular SLAM

## Текущее состояние

Сейчас `camera_publisher` публикует:

- `sensor_msgs/msg/Image` в `/camera/image_raw`;
- `sensor_msgs/msg/CameraInfo` в `/camera/camera_info`.

Если реальные параметры калибровки ещё не получены, узел использует шаблонный `CameraInfo`, вычисленный от текущего размера кадра. Для визуального SLAM этого недостаточно: перед интеграцией SLAM необходимо заменить шаблонные матрицы на реальные.

## Что уже подготовлено

- параметры калибровки (`distortion_model`, `distortion_coefficients`, `camera_matrix`, `rectification_matrix`, `projection_matrix`) уже встроены в `camera_publisher`;
- есть шаблон `config/camera_calibration.template.yaml`;
- `CameraInfo` публикуется синхронно с каждым кадром и имеет тот же `frame_id`, что и изображение.

## Рекомендуемый следующий этап — калибровка

### 1. Собрать пакет и запустить publisher

```powershell
.\scripts\build_workspace.ps1
.\scripts\run_camera_publisher.ps1
```

### 2. Запустить инструмент калибровки ROS 2

В отдельном окне с тем же окружением:

```cmd
scripts\run_in_ros_env.cmd ros2 run camera_calibration cameracalibrator --size 8x6 --square 0.025 image:=/camera/image_raw camera:=/camera
```

Где:

- `--size 8x6` — число внутренних углов шахматной доски;
- `--square 0.025` — длина стороны клетки в метрах;
- `image:=/camera/image_raw` — топик изображения;
- `camera:=/camera` — базовый namespace, под которым доступен `camera_info`.

### 3. Сохранить результаты

После успешной калибровки перенесите значения в отдельный YAML-файл, например `config/camera_calibration.local.yaml`, по образцу `config/camera_calibration.template.yaml`.

### 4. Запускать publisher с реальной калибровкой

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args --params-file C:\dev\ros2_ws\src\yoga_cam_sub\config\camera_calibration.local.yaml
```

Либо через launch:

```cmd
scripts\run_in_ros_env.cmd ros2 launch yoga_cam_sub camera_publisher.launch.py params_file:=C:\dev\ros2_ws\src\yoga_cam_sub\config\camera_calibration.local.yaml
```

## Что ещё нужно для visual SLAM

### TF-дерево

SLAM-пакетам обычно нужен стабильный `frame_id`, например:

- `base_link`
- `camera_link`
- `camera_optical_frame`

Рекомендуется добавить статический TF между `camera_link` и `camera_optical_frame`, если дальше будет использоваться стандартная ROS-геометрия камеры.

### Стабильные timestamp

Для monocular SLAM важны стабильные временные метки. Сейчас `camera_publisher` ставит `this->now()` в момент публикации. Для ноутбучной камеры этого обычно достаточно на этапе прототипирования, но позже можно улучшить:

- измерение фактической частоты кадров;
- диагностику пропуска кадров;
- логирование джиттера между кадрами;
- публикацию диагностического статуса.

### Выбор следующего SLAM-пакета

Для следующего шага можно рассматривать:

1. `rtabmap_ros` — если нужен более ROS-ориентированный и быстрый старт;
2. обёртку над ORB-SLAM3 — если нужен классический monocular pipeline;
3. собственный промежуточный preprocessing слой — если планируется экспериментальная цепочка.

## Минимальный чек-лист перед интеграцией SLAM

- подтверждено, что `camera_publisher` стабильно публикует реальные кадры;
- подтверждено, что `/camera/camera_info` содержит реальные матрицы калибровки;
- согласован `frame_id` и базовые TF;
- выбрано разрешение и FPS, которые тянет ноутбук без заметных пропусков;
- зафиксирован пакет/ветка с рабочей конфигурацией камеры.
