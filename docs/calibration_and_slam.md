# Переход к калибровке и monocular SLAM

## Текущее состояние

Сейчас `camera_publisher` публикует:

- `sensor_msgs/msg/Image` в `/camera/image_raw`;
- `sensor_msgs/msg/CameraInfo` в `/camera/camera_info`.

Если реальные параметры калибровки ещё не получены, узел использует шаблонный `CameraInfo`, вычисленный от текущего размера кадра. Для visual SLAM этого недостаточно: перед интеграцией SLAM нужно заменить шаблонные матрицы на реальные.

## Что уже подготовлено

- параметры калибровки (`distortion_model`, `distortion_coefficients`, `camera_matrix`, `rectification_matrix`, `projection_matrix`) уже встроены в `camera_publisher`;
- есть шаблон `config/camera_calibration.template.yaml`;
- добавлен скрипт `scripts/run_camera_calibration.ps1`, который готовит publisher, проверяет наличие `camera_calibration` и формирует точную команду запуска;
- `CameraInfo` публикуется синхронно с каждым кадром и имеет тот же `frame_id`, что и изображение.

## Рекомендуемый следующий этап — калибровка

### 1. Собрать пакет и запустить базовые проверки

```powershell
.\scripts\build_workspace.ps1
.\scripts\full_validation.ps1
```

### 2. Проверить доступность калибратора

```powershell
.\scripts\run_camera_calibration.ps1 -CheckOnly
```

Скрипт:

- проверяет наличие `camera_calibration` в текущем underlay;
- подсказывает итоговую команду запуска;
- сообщает, если Windows-бинарное окружение не содержит GUI-калибратор.

### 3. Запустить калибровку, если инструмент установлен

```powershell
.\scripts\run_camera_calibration.ps1 -BoardWidth 8 -BoardHeight 6 -SquareSize 0.025
```

Где:

- `BoardWidth` и `BoardHeight` — количество внутренних углов шахматной доски;
- `SquareSize` — длина стороны клетки в метрах;
- `ImageTopic` и `CameraNamespace` при необходимости можно переопределить параметрами скрипта.

### 4. Если `camera_calibration` недоступен в Windows underlay

В текущем окружении может отсутствовать пакет `camera_calibration` как исполняемый GUI-инструмент. В этом случае есть два практических варианта:

1. использовать Linux/WSL/другую ROS 2 машину с установленным `camera_calibration`, публикуя в неё поток камеры;
2. выполнить калибровку внешним инструментом OpenCV и перенести матрицы в YAML вручную.

### 5. Сохранить результаты

После успешной калибровки перенесите значения в отдельный YAML-файл, например `config/camera_calibration.local.yaml`, по образцу `config/camera_calibration.template.yaml`.

### 6. Запускать publisher с реальной калибровкой

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args --params-file C:\dev\ros2_ws\src\yoga_cam_sub\config\camera_calibration.local.yaml
```

Либо через launch:

```cmd
scripts\run_in_ros_env.cmd ros2 launch yoga_cam_sub camera_publisher.launch.py params_file:=C:\dev\ros2_ws\src\yoga_cam_sub\config\camera_calibration.local.yaml
```

## Что ещё нужно для visual SLAM

### TF-дерево

SLAM-пакетам обычно нужен стабильный набор frame-ов, например:

- `base_link`
- `camera_link`
- `camera_optical_frame`

Рекомендуется добавить статический TF между `camera_link` и `camera_optical_frame`, если дальше будет использоваться стандартная ROS-геометрия камеры.

### Стабильные timestamp

Для monocular SLAM важны стабильные временные метки. Сейчас `camera_publisher` ставит `this->now()` в момент публикации. Для ноутбучной камеры этого обычно достаточно на этапе прототипирования, но позже полезно добавить:

- измерение фактической частоты кадров;
- диагностику пропуска кадров;
- логирование джиттера между кадрами;
- публикацию диагностического статуса.

### Выбор следующего SLAM-пакета

Для следующего шага можно рассматривать:

1. `rtabmap_ros` — если нужен более ROS-ориентированный и быстрый старт;
2. обёртку над ORB-SLAM3 — если нужен классический monocular pipeline;
3. собственный preprocessing-слой — если планируется экспериментальная цепочка.

## Минимальный чек-лист перед интеграцией SLAM

- подтверждено, что `camera_publisher` стабильно публикует реальные кадры;
- подтверждено, что `/camera/camera_info` содержит реальные матрицы калибровки;
- согласованы `frame_id` и базовые TF;
- выбраны разрешение и FPS, которые ноутбук тянет без заметных пропусков;
- зафиксирована рабочая ветка и конфигурация камеры.
