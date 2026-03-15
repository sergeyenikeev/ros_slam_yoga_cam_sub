# Обзор кодовой базы и ключевых файлов

Этот документ нужен, чтобы быстро понять архитектуру пакета `yoga_cam_sub`, не перечитывая весь репозиторий с нуля.

## 1. Общая архитектура

Пакет состоит из четырёх основных слоёв:

1. **Источник данных** — `camera_publisher`, который читает ноутбучную камеру через OpenCV и публикует ROS 2 сообщения.
2. **Проверки входного потока** — `image_counter`, `camera_slam_preflight`, `camera_feature_monitor`.
3. **Чистая библиотечная логика** — `camera_utils`, `stream_diagnostics`, `feature_diagnostics`.
4. **PowerShell automation** — сборка, проверка, запись bag, отчёты, experiment workflow.

Главный инженерный принцип здесь такой: всё, что можно тестировать без железа, вынесено из runtime-нод в чистые функции и покрыто unit-тестами.

## 2. Ключевые C++ файлы

### `src/camera_publisher.cpp`

Главный runtime-узел проекта.

Что делает:

- читает параметры камеры и калибровки;
- поднимает `cv::VideoCapture` с fallback по backend OpenCV;
- публикует `sensor_msgs/msg/Image` в `/camera/image_raw`;
- публикует `sensor_msgs/msg/CameraInfo` в `/camera/camera_info`;
- умеет использовать либо inline calibration parameters, либо `calibration_file`;
- умеет восстанавливаться после серии ошибок чтения камеры;
- ведёт подробные runtime-логи.

На что смотреть в коде в первую очередь:

- `load_parameters()` — какие параметры вообще есть у publisher;
- `preload_calibration_source()` — как загружается YAML-калибровка;
- `open_camera()` / `try_open_camera()` — логика backend selection;
- `attempt_recover_after_failed_reads()` — recovery path;
- `refresh_calibration_if_needed()` — масштабирование калибровки под runtime-размер;
- `publish_frame()` — основная логика цикла публикации.

### `src/image_counter.cpp`

Минимальный subscriber для smoke-проверок.

Что делает:

- подписывается на `Image`;
- логирует параметры входного кадра;
- умеет завершаться после `max_frames`;
- используется и как ручной диагностический узел, и как основа для автоматических smoke-тестов.

Это самый простой и надёжный consumer потока в репозитории.

### `src/camera_slam_preflight.cpp`

Проверка того, что входной поток вообще годится для следующего шага SLAM.

Что делает:

- подписывается на `Image` и `CameraInfo`;
- проверяет совпадение размеров и `frame_id`;
- проверяет, что поток не разваливается по времени;
- считает FPS и джиттер;
- предупреждает, если `CameraInfo` похож на шаблонный, а не на реальную калибровку;
- завершает прогон статусом success/failure.

Именно этот узел отвечает на вопрос: "входной ROS-поток структурно готов к SLAM?"

### `src/camera_feature_monitor.cpp`

Проверка не структуры потока, а его визуальной ценности для monocular SLAM.

Что делает:

- подписывается на `Image`;
- конвертирует сообщение в BGR-кадр OpenCV;
- считает ORB-feature, покрытие сетки, резкость, яркость и контраст;
- агрегирует summary по нескольким кадрам;
- валит прогон, если поток беден на ориентиры или визуально деградирован.

Именно этот узел отвечает на вопрос: "в кадре вообще есть что трекать?"

### `src/camera_calibration_inspector.cpp`

Небольшой служебный runtime-узел.

Что делает:

- загружает YAML-калибровку;
- валидирует обязательные поля;
- проверяет масштабирование под другое разрешение;
- используется скриптами импорта/проверки calibration file.

### `src/camera_utils.cpp`

Главная библиотека вокруг runtime-камеры.

Что внутри:

- валидация `CameraParameters`;
- подготовка `cv::Mat` для публикации;
- сборка `sensor_msgs/msg/Image`;
- формирование `CameraCalibration` и `CameraInfo`;
- загрузка YAML-калибровки;
- масштабирование матриц под другой размер кадра;
- описание backend OpenCV и backend-priority helpers.

Это самый важный reusable файл в репозитории: его надо менять аккуратно и всегда вместе с тестами.

### `src/stream_diagnostics.cpp`

Чистая логика preflight-проверок.

Что делает:

- считает timing statistics по timestamps;
- проверяет согласованность `Image` и `CameraInfo`;
- распознаёт шаблонную калибровку.

Плюс этого файла в том, что он не зависит от живой камеры и полностью покрывается unit-тестами.

### `src/feature_diagnostics.cpp`

Чистая логика feature-аналитики.

Что делает:

- конвертирует `sensor_msgs/Image` в BGR `cv::Mat`;
- считает ORB keypoints;
- оценивает grid coverage;
- считает blur score через дисперсию лапласиана;
- агрегирует frame-level metrics в summary;
- валидирует summary against thresholds.

Это основа для дальнейшей SLAM-диагностики и experiment scoring.

## 3. Заголовочные файлы

### `include/yoga_cam_sub/camera_utils.hpp`

Публичный контракт для camera runtime helpers:

- `CameraParameters`
- `CameraCalibration`
- validate/build/load/scale functions
- backend priority helpers

### `include/yoga_cam_sub/stream_diagnostics.hpp`

Публичный контракт для preflight-аналитики:

- `StreamTimingStatistics`
- `calculate_timing_statistics()`
- `validate_image_and_camera_info()`
- `camera_info_matches_template()`

### `include/yoga_cam_sub/feature_diagnostics.hpp`

Публичный контракт для feature-аналитики:

- `FeatureFrameMetrics`
- `FeatureMonitorThresholds`
- `FeatureMonitorSummary`
- conversion/analyze/summarize/validate functions

## 4. Launch-файлы

### `launch/camera_publisher.launch.py`

Запускает только publisher камеры с параметрами из `config/camera_publisher.params.yaml`.

### `launch/camera_pipeline.launch.py`

Запускает связку `camera_publisher + image_counter`.

Подходит для ручной проверки, что subscriber действительно читает поток.

### `launch/camera_slam_preflight.launch.py`

Запускает `camera_publisher + camera_slam_preflight` в одном reproducible сценарии.

### `launch/camera_feature_monitor.launch.py`

Запускает `camera_publisher + camera_feature_monitor`.

Это быстрый способ проверить scene quality без ручной сборки команды.

### `launch/static_camera_tf.launch.py`

Публикует `camera_link -> camera_optical_frame`.

### `launch/camera_slam_ready.launch.py`

Собирает минимально готовую к SLAM конфигурацию:

- `camera_publisher`
- статический TF

Именно этот launch используется для записи bag-датасетов.

## 5. Ключевые PowerShell-скрипты

### `scripts/run_in_ros_env.cmd`

Самый важный infrastructure wrapper.

Что делает:

- инициализирует `vcvars64.bat`;
- выставляет `VisualStudioVersion=17.0`;
- добавляет `Ninja`, pixi env, ROS underlay и overlay в `PATH`;
- запускает ROS/colcon команды в совместимом Windows-окружении.

Если когда-либо ломается сборка на Windows, первым делом нужно проверять именно этот wrapper.

### `scripts/build_workspace.ps1`

Официальная сборка пакета через `colcon build`.

### `scripts/run_tests.ps1`

Официальный запуск unit/lint тестов.

### `scripts/full_validation.ps1`

Главный orchestrator полного прогона.

Именно он собирает в один сценарий:

- диагностику окружения;
- сборку;
- тесты;
- smoke-проверки;
- bag workflow;
- experiment smoke.

### `scripts/check_topics.ps1`

Поднимает publisher и подтверждает, что `/camera/image_raw` и `/camera/camera_info` реально существуют и читаются через `ros2 topic echo --once`.

### `scripts/run_dataset_record.ps1`

Ключевой dataset recorder.

Что делает:

- запускает `camera_slam_ready.launch.py`;
- пишет `/camera/image_raw`, `/camera/camera_info`, `/tf_static` в bag;
- автоматически делает `reindex`;
- собирает `dataset_manifest.json`;
- обновляет `dataset_catalog.json`.

### `scripts/run_dataset_playback.ps1`

Универсальный playback runner.

Умеет запускать bag вместе с:

- `image_counter`;
- `camera_slam_preflight`;
- `camera_feature_monitor`.

Это базовый orchestrator для offline-аналитики.

### `scripts/run_dataset_report.ps1`

Строит preflight JSON-report по dataset.

### `scripts/run_dataset_feature_report.ps1`

Строит feature JSON-report по dataset.

### `scripts/run_slam_experiment.ps1`

Собирает единый пакет эксперимента:

- manifest эксперимента;
- preflight report;
- feature report;
- markdown summary;
- effective config.

Это следующий шаг от "у нас есть bag" к "у нас есть воспроизводимый SLAM experiment packet".

### `scripts/update_dataset_catalog.ps1`

Пересобирает сводный каталог datasets.

### `scripts/dataset_catalog_utils.ps1`

Общий helper-модуль для manifest/catalog/report workflow.

Этот файл стоит считать служебной библиотекой PowerShell-автоматизации.

## 6. Unit-тесты

### `test/test_camera_utils.cpp`

Покрывает:

- параметры камеры;
- преобразование кадров;
- сборку `Image`;
- сборку и загрузку `CameraInfo`/калибровки;
- backend helpers.

### `test/test_stream_diagnostics.cpp`

Покрывает preflight-логику без железа.

### `test/test_feature_diagnostics.cpp`

Покрывает feature-логику без железа:

- conversion из `Image`;
- ORB/blur/brightness summary;
- threshold validation.

## 7. Конфигурация и шаблоны

### `config/camera_publisher.params.yaml`

Базовые параметры launch-сценариев.

### `config/camera_calibration.template.yaml`

Шаблон для ручного заполнения калибровки.

### `config/camera_calibration.sample.yaml`

Пример корректного стандартного YAML.

### `config/camera_calibration.local.yaml`

Локальная рабочая калибровка после импорта.

### `config/slam_experiment.template.json`

Шаблон конфигурации эксперимента для будущего SLAM backend.

## 8. Как читать проект сверху вниз

Если вы новый человек в проекте, самый короткий маршрут такой:

1. `README.md`
2. `docs/remaining_work_plan.md`
3. `src/camera_publisher.cpp`
4. `src/camera_slam_preflight.cpp`
5. `src/camera_feature_monitor.cpp`
6. `src/camera_utils.cpp`
7. `scripts/full_validation.ps1`
8. `scripts/run_dataset_record.ps1`
9. `scripts/run_slam_experiment.ps1`

После этого уже можно осознанно менять pipeline и добавлять реальный SLAM backend.
