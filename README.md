# yoga_cam_sub

`yoga_cam_sub` — ROS 2 Jazzy пакет на C++ для публикации кадров со встроенной камеры ноутбука в топики `/camera/image_raw` и `/camera/camera_info`, а также для подготовки основы под monocular visual SLAM на Windows 11.

## Что уже сделано

- реализован собственный узел `camera_publisher` на C++ с публикацией `sensor_msgs/msg/Image` и `sensor_msgs/msg/CameraInfo`;
- реализован диагностический subscriber `image_counter` с параметрами `image_topic` и `max_frames`;
- вынесена тестируемая логика подготовки кадров и `CameraInfo` в библиотеку `camera_utils`;
- добавлены unit-тесты для валидации параметров, преобразования кадров, генерации `Image` и `CameraInfo`;
- добавлены launch-файлы, smoke-тесты, сценарий полного прогона и скрипты сборки/диагностики;
- добавлен сценарий подготовки калибровки `scripts/run_camera_calibration.ps1` с проверкой наличия инструмента `camera_calibration`;
- добавлен импорт стандартного YAML из `camera_calibration` через `calibration_file` и отдельный валидатор `camera_calibration_inspector`;
- подготовлены шаблоны параметров и документация для следующего этапа интеграции visual SLAM.

## Структура пакета

- `src/camera_publisher.cpp` — основной publisher камеры;
- `src/image_counter.cpp` — subscriber для проверки потока изображений;
- `src/camera_utils.cpp` и `include/yoga_cam_sub/camera_utils.hpp` — тестируемая логика преобразования кадров и подготовки `CameraInfo`;
- `config/camera_publisher.params.yaml` — базовые параметры узлов;
- `config/camera_calibration.template.yaml` — шаблон для реальной калибровки;
- `config/camera_calibration.sample.yaml` — пример стандартного YAML-файла от `camera_calibration`;
- `launch/camera_publisher.launch.py` — запуск только publisher;
- `launch/camera_pipeline.launch.py` — совместный запуск publisher и subscriber;
- `launch/static_camera_tf.launch.py` — публикация статического TF между `camera_link` и `camera_optical_frame`;
- `launch/camera_slam_ready.launch.py` — связка publisher + статический TF для следующего этапа SLAM;
- `scripts/full_validation.ps1` — единый автоматический прогон всех доступных проверок;
- `scripts/run_camera_calibration.ps1` — подготовка и запуск калибровки камеры;
- `scripts/import_camera_calibration.ps1` — импорт и валидация YAML-калибровки;
- `scripts/tf_smoke_test.ps1` — автоматическая проверка публикации статического TF;
- `scripts/run_slam_ready_pipeline.ps1` — запуск SLAM-ready конфигурации камеры;
- `docs/` — подробная документация по сборке, ручной проверке и подготовке к SLAM.

## Быстрый старт

### 1. Сборка

```powershell
.\scripts\build_workspace.ps1
```

Или через `.cmd`:

```cmd
scripts\build_workspace.cmd
```

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

### 5. Полный автоматический прогон

```powershell
.\scripts\full_validation.ps1
```

Сценарий последовательно выполняет диагностику окружения, сборку, unit/lint тесты, smoke-тест subscriber, проверку реальных топиков и launch smoke-тест.

### 6. Подготовка калибровки

Проверить готовность среды и получить точную команду запуска:

```powershell
.\scripts\run_camera_calibration.ps1 -CheckOnly
```

Если инструмент `camera_calibration` установлен, можно запускать его тем же скриптом без `-CheckOnly`.

### 7. Импорт готового YAML калибровки

Когда `camera_calibration` сохранит `ost.yaml` или другой стандартный YAML, импортируйте его в пакет:

```powershell
.\scripts\import_camera_calibration.ps1 -SourceFile C:\путь\к\ost.yaml
```

Скрипт скопирует файл в `config/camera_calibration.local.yaml`, прогонит валидацию через `camera_calibration_inspector` и выведет готовые команды запуска.

### 8. Запуск SLAM-ready конфигурации

```powershell
.\scripts\run_slam_ready_pipeline.ps1
```

Эта команда запускает `camera_publisher` и статический TF `camera_link -> camera_optical_frame`.

## Важные параметры `camera_publisher`

- `device_index` — индекс камеры OpenCV;
- `width`, `height` — желаемое разрешение захвата;
- `fps` — целевая частота кадров;
- `frame_id` — `frame_id` для `Image` и `CameraInfo`;
- `image_topic` — топик для изображений, по умолчанию `/camera/image_raw`;
- `camera_info_topic` — топик для `CameraInfo`, по умолчанию `/camera/camera_info`;
- `use_msmf` — сначала пробовать `CAP_MSMF`, затем fallback на `CAP_ANY`;
- `max_frames` — число кадров до автоостановки, `0` означает бесконечный режим;
- `calibration_file` — путь к стандартному YAML-файлу от `camera_calibration`;
- `distortion_model`, `distortion_coefficients`, `camera_matrix`, `rectification_matrix`, `projection_matrix` — параметры будущей калибровки.

Если задан `calibration_file`, он имеет приоритет над inline-параметрами калибровки. Если ни файл, ни массивы не заданы, узел публикует шаблонный `CameraInfo` с безопасными стартовыми значениями. Для SLAM их нужно заменить реальной калибровкой.

## Smoke-тест без физической камеры

```powershell
.\scripts\subscriber_smoke_test.ps1
```

Скрипт поднимает `image_counter`, публикует синтетическое сообщение в `/camera/image_raw` и проверяет, что subscriber получил кадр.

## Диагностика окружения

```powershell
.\scripts\diagnose_environment.ps1
```

Скрипт проверяет наличие `cl`, `ninja`, `ros2`, `colcon`, выводит `cmake --version` и наличие пакета `yoga_cam_sub` в `ros2 pkg list`.

Проверить только участок статического TF можно отдельно:

```powershell
.\scripts\tf_smoke_test.ps1
```

## Почему раньше падала сборка

Проблема была не в самом `CMakeLists.txt`, а в окружении запуска `colcon`:

- CMake вызывался с `-GNinja`, но `ninja.exe` отсутствовал в `PATH`;
- одновременно в окружении отсутствовали `cl.exe`, `INCLUDE`, `LIB` и другие переменные x64 toolchain;
- Visual Studio 2026 сообщает версию `18.0`, тогда как часть ROS/colcon-цепочки всё ещё ожидает `17.0`.

Эти проблемы закрывает `scripts/run_in_ros_env.cmd`, который инициализирует `vcvars64.bat`, выставляет `VisualStudioVersion=17.0`, подключает pixi-окружение, ROS underlay и overlay workspace.

## Ограничения автоматической проверки

Пакет можно полностью собрать и частично протестировать без камеры, но публикацию реальных кадров и реальную калибровку нужно подтверждать на машине с физическим доступом к встроенной камере.

## Следующие шаги

1. Выполнить реальную калибровку камеры и сохранить матрицы в отдельный YAML-файл.
2. Импортировать YAML через `scripts/import_camera_calibration.ps1` и запустить pipeline уже с реальным `CameraInfo`.
3. Подстроить параметры статического TF под реальное положение камеры на ноутбуке или на роботе.
4. Подключить следующий monocular SLAM-модуль к `/camera/image_raw` и `/camera/camera_info`.
5. При необходимости расширить пакет диагностикой джиттера, пропуска кадров и transport-вариантами.

## Дополнительная документация

- `docs/windows_build.md` — настройка сборки и разбор Windows-окружения;
- `docs/manual_camera_verification.md` — ручная проверка камеры и топиков;
- `docs/calibration_and_slam.md` — переход к калибровке камеры и следующему шагу visual SLAM.
