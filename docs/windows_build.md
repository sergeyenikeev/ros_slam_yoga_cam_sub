# Сборка на Windows 11

## Подтверждённая конфигурация

- Windows 11
- ROS 2 Jazzy binary underlay: `C:\pixi_ws\ros2-windows`
- workspace: `C:\dev\ros2_ws`
- пакет: `C:\dev\ros2_ws\src\yoga_cam_sub`
- Visual Studio 2026, MSVC x64
- pixi: `C:\Users\senik\.pixi\bin\pixi.exe`
- OpenCV из pixi-окружения `C:\pixi_ws\.pixi\envs\default`

## Корневая причина ошибки CMake

Ошибка вида:

```text
CMake Error: CMake was unable to find a build program corresponding to "Ninja".
CMAKE_C_COMPILER not set, after EnableLanguage
CMAKE_CXX_COMPILER not set, after EnableLanguage
```

возникала, когда `colcon build` запускался без предварительной инициализации x64 toolchain Visual Studio.

Это приводило сразу к трём последствиям:

1. `ninja.exe` не находился в `PATH`;
2. `cl.exe` не находился в `PATH`;
3. в окружении отсутствовали `INCLUDE`, `LIB`, `LIBPATH`, `VCToolsInstallDir` и другие переменные, которые выставляет `vcvars64.bat`.

Дополнительно Visual Studio 2026 сообщает версию `18.0`, а часть ROS/colcon-цепочки пока ожидает `17.0`, поэтому нужен явный обход через:

```cmd
set VisualStudioVersion=17.0
```

## Как это исправлено

В пакет добавлен `scripts/run_in_ros_env.cmd`, который автоматически:

- находит `vcvars64.bat` через `vswhere`;
- инициализирует x64 toolchain;
- выставляет `VisualStudioVersion=17.0`;
- включает UTF-8 для `cmd.exe` и Python;
- добавляет `Ninja`, `colcon`, OpenCV и pixi env в `PATH`;
- выставляет `CMAKE_GENERATOR=Ninja` и `CMAKE_MAKE_PROGRAM`;
- подключает ROS underlay и overlay workspace.

Именно этот wrapper используется всеми `.ps1`/`.cmd` командами пакета.

## Рекомендуемая сборка

Из каталога пакета:

```powershell
.\scripts\build_workspace.ps1
```

Или:

```cmd
scripts\build_workspace.cmd
```

## Ручной эквивалент без скриптов

Если нужно собрать вручную в одном `cmd.exe` окне:

```cmd
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat"
set VisualStudioVersion=17.0
set CMAKE_GENERATOR=Ninja
set CMAKE_MAKE_PROGRAM=C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe
set OpenCV_DIR=C:\pixi_ws\.pixi\envs\default\Library\cmake
set PATH=C:\pixi_ws\.pixi\envs\default;C:\pixi_ws\.pixi\envs\default\Library\bin;C:\pixi_ws\.pixi\envs\default\Scripts;%PATH%
call C:\pixi_ws\ros2-windows\local_setup.bat
cd /d C:\dev\ros2_ws
colcon build --merge-install --packages-select yoga_cam_sub --cmake-clean-cache --cmake-force-configure --cmake-args -GNinja -DCMAKE_BUILD_TYPE=Release
```

## Диагностика

Быстрая автоматическая проверка:

```powershell
.\scripts\diagnose_environment.ps1
```

Полный автоматический прогон:

```powershell
.\scripts\full_validation.ps1
```

Отдельная проверка runtime-обработки YAML калибровки:

```powershell
.\scripts\calibration_file_smoke_test.ps1
```

Отдельная preflight-проверка потока камеры перед SLAM:

```powershell
.\scripts\slam_preflight_smoke_test.ps1
```

Отдельная проверка записи и воспроизведения bag-датасета:

```powershell
.\scripts\dataset_bag_smoke_test.ps1
```

Отдельная проверка статического TF:

```powershell
.\scripts\tf_smoke_test.ps1
```

Полезные команды внутри инициализированного окружения:

```cmd
where cl
where ninja
where ros2
where colcon
cmake --version
ros2 pkg list | findstr yoga_cam_sub
```

## Частые проблемы

### `OpenCV` не находится

Проверьте, что существует путь:

```text
C:\pixi_ws\.pixi\envs\default\Library\cmake\OpenCVConfig.cmake
```

и что переменная `OpenCV_DIR` выставляется скриптом `run_in_ros_env.cmd`.

### `ros2` находится, а `colcon` нет

`ros2` идёт из underlay `ros2-windows`, а `colcon` — из pixi-окружения. Нужны оба источника в `PATH`.

### Пакет не виден через `ros2 pkg list`

После успешной сборки команды нужно запускать из окружения, где подключён overlay `C:\dev\ros2_ws\install\local_setup.bat`. Скрипт `run_in_ros_env.cmd` делает это автоматически, если каталог `install` уже существует.

### Нужно быстро проверить YAML калибровки без запуска камеры

Используйте:

```powershell
.\scripts\import_camera_calibration.ps1 -SourceFile C:\путь\к\ost.yaml
```

Скрипт валидирует файл через `camera_calibration_inspector` и подсказывает готовую команду запуска с `calibration_file`.

### Нужно быстро понять, готов ли поток к SLAM

Используйте:

```powershell
.\scripts\run_slam_preflight.ps1 calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

Сценарий проверяет согласованность `Image`/`CameraInfo` и печатает фактический FPS потока.

### Нужно записать повторяемый offline-датасет

Используйте:

```powershell
.\scripts\run_dataset_record.ps1 -DurationSeconds 5
```

По умолчанию будет использован storage `sqlite3`, потому что на Windows он стабильнее для сценария "записать по таймеру -> reindex -> сразу воспроизвести".

После этого bag можно воспроизводить командой:

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunPreflight
```

Если нужен сохраняемый JSON-отчёт по offline-прогону, используйте:

```powershell
.\scripts\run_dataset_report.ps1 -BagPath C:\путь\к\bag
```

### В консоли виден warning про RTI Connext DDS

Предупреждение вида `RTI Connext DDS environment script not found` в этом проекте не блокирует работу, потому что пакет проверен с `rmw_fastrtps_cpp`.
