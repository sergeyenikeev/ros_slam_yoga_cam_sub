# yoga_cam_sub

`yoga_cam_sub` — ROS 2 Jazzy пакет на C++ для публикации кадров со встроенной камеры ноутбука в топики `/camera/image_raw` и `/camera/camera_info`, а также для базовой подготовки monocular visual SLAM конвейера на Windows 11.

## Что уже сделано

- реализован собственный узел `camera_publisher` на C++ с публикацией `sensor_msgs/msg/Image` и `sensor_msgs/msg/CameraInfo`;
- реализован диагностический subscriber `image_counter` с параметром `image_topic` и опцией автоостановки `max_frames`;
- добавлены подробные логи запуска, параметров, открытия камеры, публикации кадров и ошибок;
- вынесена тестируемая логика подготовки кадров и `CameraInfo` в библиотеку `camera_utils`;
- добавлены unit-тесты для проверки валидации параметров, преобразования кадров и генерации сообщений;
- добавлены launch-файлы, шаблоны параметров и скрипты для сборки, запуска, smoke-тестов и диагностики окружения;
- подготовлен шаблон параметров для дальнейшей калибровки камеры.

## Структура пакета

- `src/camera_publisher.cpp` — основной publisher камеры;
- `src/image_counter.cpp` — subscriber для проверки потока изображений;
- `src/camera_utils.cpp` и `include/yoga_cam_sub/camera_utils.hpp` — тестируемая логика преобразования кадров и `CameraInfo`;
- `config/camera_publisher.params.yaml` — базовые параметры узлов;
- `config/camera_calibration.template.yaml` — шаблон для будущей калибровки;
- `launch/camera_publisher.launch.py` — запуск только publisher;
- `launch/camera_pipeline.launch.py` — совместный запуск publisher и subscriber;
- `scripts/` — скрипты сборки, запуска, диагностики и smoke-тестов;
- `test/test_camera_utils.cpp` — unit-тесты;
- `docs/` — подробная документация.

## Быстрый старт

### 1. Сборка

Из каталога пакета:

```powershell
.\scripts\build_workspace.ps1
```

Или через `.cmd`:

```cmd
scripts\build_workspace.cmd
```

Скрипт автоматически:

- находит `vcvars64.bat` для x64 toolchain Visual Studio;
- выставляет `VisualStudioVersion=17.0` как обход для Visual Studio 2026;
- добавляет `Ninja`, `colcon` и OpenCV из pixi-окружения;
- подключает `C:\pixi_ws\ros2-windows` как underlay;
- запускает `colcon build --merge-install --packages-select yoga_cam_sub`.

### 2. Запуск publisher

```powershell
.\scripts\run_camera_publisher.ps1 --ros-args -p device_index:=0 -p width:=640 -p height:=360 -p fps:=30.0
```

### 3. Запуск publisher + subscriber

```powershell
.\scripts\run_camera_pipeline.ps1
```

### 4. Проверка топиков

Когда `camera_publisher` уже работает:

```powershell
.\scripts\check_topics.ps1 -EchoMessages
```

## Важные параметры `camera_publisher`

- `device_index` — индекс камеры OpenCV;
- `width`, `height` — желаемое разрешение захвата;
- `fps` — целевая частота кадров;
- `frame_id` — `frame_id` для `Image` и `CameraInfo`;
- `image_topic` — топик для изображений, по умолчанию `/camera/image_raw`;
- `camera_info_topic` — топик для `CameraInfo`, по умолчанию `/camera/camera_info`;
- `use_msmf` — сначала пробовать `CAP_MSMF`, затем fallback на `CAP_ANY`;
- `max_frames` — число кадров до автоостановки, `0` означает бесконечный режим;
- `distortion_model`, `distortion_coefficients`, `camera_matrix`, `rectification_matrix`, `projection_matrix` — параметры будущей калибровки.

Если массивы калибровки пустые, узел публикует шаблонный `CameraInfo` с разумными стартовыми значениями, но для SLAM их нужно заменить реальной калибровкой.

## Smoke-тест без физической камеры

Проверить `image_counter` можно даже без доступа к камере:

```powershell
.\scripts\subscriber_smoke_test.ps1
```

Скрипт поднимает `image_counter`, публикует синтетическое сообщение в `/camera/image_raw` и проверяет, что subscriber получил кадр.

## Диагностика окружения

```powershell
.\scripts\diagnose_environment.ps1
```

Скрипт проверяет наличие `cl`, `ninja`, `ros2`, `colcon`, а также выводит `cmake --version` и наличие пакета `yoga_cam_sub` в `ros2 pkg list`.

## Почему раньше падала сборка

Проблема была не в самом `CMakeLists.txt`, а в окружении запуска `colcon`:

- CMake вызывался с `-GNinja`, но `ninja.exe` отсутствовал в `PATH`;
- одновременно в окружении отсутствовали `cl.exe`, `INCLUDE`, `LIB` и другие переменные x64 toolchain;
- поэтому CMake не мог определить ни build program, ни C/C++ compiler.

Подробности и разбор зафиксированы в `docs/windows_build.md`.

## Ограничения автоматической проверки

Этот пакет можно полностью собрать и протестировать без камеры, но публикацию реальных кадров из `camera_publisher` нужно подтверждать на машине с доступом к встроенной камере.

## Следующие шаги

1. Выполнить калибровку камеры и записать реальные матрицы в `config/camera_calibration.template.yaml` или отдельный параметрический файл.
2. Добавить статическое преобразование `camera_optical_frame` в TF-дерево робота.
3. Выбрать следующий модуль SLAM и подготовить синхронизацию с `CameraInfo`.
4. При необходимости расширить пакет на публикацию `compressed`/`image_transport` и timestamp-диагностику.

## Дополнительная документация

- `docs/windows_build.md` — настройка сборки и разбор Windows-окружения;
- `docs/calibration_and_slam.md` — переход к калибровке камеры и дальнейшему visual SLAM pipeline.
