# Переход к калибровке и monocular SLAM

## Текущее состояние

Сейчас `camera_publisher` публикует:

- `sensor_msgs/msg/Image` в `/camera/image_raw`;
- `sensor_msgs/msg/CameraInfo` в `/camera/camera_info`.

Если реальные параметры калибровки ещё не получены, узел использует шаблонный `CameraInfo`, вычисленный от текущего размера кадра. Для visual SLAM этого недостаточно: перед интеграцией SLAM нужно заменить шаблонные матрицы на реальные.

## Что уже подготовлено

- параметры калибровки (`distortion_model`, `distortion_coefficients`, `camera_matrix`, `rectification_matrix`, `projection_matrix`) уже встроены в `camera_publisher`;
- `camera_publisher` умеет принимать стандартный YAML от `camera_calibration` через параметр `calibration_file`;
- есть шаблон `config/camera_calibration.template.yaml`;
- есть пример стандартного YAML `config/camera_calibration.sample.yaml`;
- добавлен скрипт `scripts/run_camera_calibration.ps1`, который готовит publisher, проверяет наличие `camera_calibration` и формирует точную команду запуска;
- добавлен скрипт `scripts/import_camera_calibration.ps1`, который копирует YAML в пакет и проверяет его через `camera_calibration_inspector`;
- добавлен узел `camera_slam_preflight` и сценарий `scripts/run_slam_preflight.ps1` для проверки фактического FPS и согласованности `Image`/`CameraInfo`;
- добавлен узел `camera_feature_monitor` и сценарий `scripts/run_feature_monitor.ps1` для оценки feature-насыщенности, резкости и яркости потока;
- добавлены сценарии `run_dataset_record.ps1` и `run_dataset_playback.ps1` для записи и повторного воспроизведения SLAM-ready bag-датасета;
- добавлен launch `static_camera_tf.launch.py` и связка `camera_slam_ready.launch.py` для публикации стандартного optical TF;
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

### 5. Импортировать результаты в пакет

Если `camera_calibration` сохранил `ost.yaml` или другой стандартный YAML, импортируйте его так:

```powershell
.\scripts\import_camera_calibration.ps1 -SourceFile C:\путь\к\ost.yaml
```

Скрипт:

- копирует YAML в `config/camera_calibration.local.yaml`;
- валидирует его через `camera_calibration_inspector`;
- показывает готовые команды запуска publisher и SLAM-ready pipeline.

Если калибровка получена не в формате `camera_calibration`, можно либо привести её к стандартному YAML-формату, либо вручную заполнить `config/camera_calibration.template.yaml`.

### 6. Прогнать preflight после импорта калибровки

Перед подключением SLAM полезно сразу проверить поток:

```powershell
.\scripts\run_slam_preflight.ps1 calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

Preflight проверит:

- приходят ли оба топика `/camera/image_raw` и `/camera/camera_info`;
- совпадают ли `frame_id`, ширина и высота;
- какой реальный FPS наблюдается;
- не похож ли `CameraInfo` на шаблонную калибровку.

### 7. Записать эталонный bag после успешного preflight

Когда поток уже прошёл preflight, имеет смысл сразу сохранить воспроизводимый датасет:

```powershell
.\scripts\run_dataset_record.ps1 -DurationSeconds 5
```

По умолчанию запись идёт в `sqlite3`, чтобы повторный `ros2 bag play` на Windows сохранял корректный порядок сообщений для preflight и будущего SLAM.

А затем проверить его без живой камеры:

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunPreflight
```

При желании тот же offline-прогон можно сохранить как отдельный JSON-report:

```powershell
.\scripts\run_dataset_report.ps1 -BagPath C:\путь\к\bag
```

А если нужно понять, хватает ли в кадре визуальных ориентиров для следующего monocular SLAM шага, сохраните ещё и отдельный feature-report:

```powershell
.\scripts\run_dataset_feature_report.ps1 -BagPath C:\путь\к\bag
```

И, наконец, соберите единый пакет эксперимента:

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\путь\к\bag
```

Этот каталог потом можно будет напрямую использовать как корень для реального SLAM backend и его результатов.

Если позже появится baseline и новый кандидат, их можно сравнить offline:

```powershell
.\scripts\compare_slam_experiments.ps1 -BaselineExperiment C:\путь\к\baseline_experiment -CandidateExperiment C:\путь\к\candidate_experiment
```

Так мы заранее увидим, нет ли деградации входных метрик, ещё до анализа trajectory и map output.

### 8. Запускать publisher с реальной калибровкой

```cmd
scripts\run_in_ros_env.cmd ros2 run yoga_cam_sub camera_publisher --ros-args -p calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

Либо через launch:

```cmd
scripts\run_in_ros_env.cmd ros2 launch yoga_cam_sub camera_publisher.launch.py calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

Если runtime-разрешение отличается от исходного размера калибровки, `camera_publisher` автоматически масштабирует матрицы и пишет это в лог. При изменении aspect ratio узел дополнительно предупреждает, что для SLAM лучше перекалибровать камеру в целевом разрешении.

## Что ещё нужно для visual SLAM

### TF-дерево

SLAM-пакетам обычно нужен стабильный набор frame-ов, например:

- `base_link`
- `camera_link`
- `camera_optical_frame`

В пакете уже есть готовый launch для этого преобразования:

```cmd
scripts\run_in_ros_env.cmd ros2 launch yoga_cam_sub static_camera_tf.launch.py
```

И готовая SLAM-ready связка:

```powershell
.\scripts\run_slam_ready_pipeline.ps1
```

По умолчанию она публикует стандартный ROS optical transform `camera_link -> camera_optical_frame`. При реальном монтаже камеры смещения и углы можно переопределить launch-аргументами.

### Стабильные timestamp

Для monocular SLAM важны стабильные временные метки. Сейчас `camera_publisher` ставит `this->now()` в момент публикации. Для ноутбучной камеры этого обычно достаточно на этапе прототипирования, но позже полезно добавить:

- измерение фактической частоты кадров;
- диагностику пропуска кадров;
- логирование джиттера между кадрами;
- публикацию диагностического статуса.

Часть этой диагностики уже покрывает `camera_slam_preflight`, который измеряет фактический FPS и разброс интервалов между кадрами.

Дополнительно `camera_feature_monitor` оценивает:

- сколько ORB-feature в среднем видно на кадре;
- насколько эти feature распределены по площади изображения;
- не слишком ли картинка размазана;
- достаточно ли света для устойчивого трекинга.

Для живой проверки это можно запускать так:

```powershell
.\scripts\run_feature_monitor.ps1 publisher_max_frames:=60 required_frames:=10
```

### Выбор следующего SLAM-пакета

Для следующего шага можно рассматривать:

1. `rtabmap_ros` — если нужен более ROS-ориентированный и быстрый старт;
2. обёртку над ORB-SLAM3 — если нужен классический monocular pipeline;
3. собственный preprocessing-слой — если планируется экспериментальная цепочка.

## Минимальный чек-лист перед интеграцией SLAM

- подтверждено, что `camera_publisher` стабильно публикует реальные кадры;
- подтверждено, что `/camera/camera_info` содержит реальные матрицы калибровки;
- прогнан `camera_slam_preflight` и зафиксирован фактический FPS;
- согласованы `frame_id` и базовые TF;
- выбраны разрешение и FPS, которые ноутбук тянет без заметных пропусков;
- зафиксирована рабочая ветка и конфигурация камеры.
