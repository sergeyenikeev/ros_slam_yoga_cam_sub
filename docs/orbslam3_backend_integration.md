# Подробный runbook по ORB-SLAM3 интеграции

Этот документ описывает не только архитектурную идею, но и практический порядок действий:

1. что уже делает сам `yoga_cam_sub`;
2. что нужно установить вне репозитория;
3. что нужно подготовить в конфиге;
4. какие команды запускать;
5. как понять, что всё сработало;
6. какие типовые проблемы ожидать на Windows.

Документ рассчитан на сценарий, где `yoga_cam_sub` уже собран и используется как reproducible experiment workflow, а ORB-SLAM3 подключается как внешний monocular backend.

## 1. Что уже есть в репозитории

Слой `yoga_cam_sub` уже закрывает подготовку входных данных и orchestration вокруг backend:

- публикацию `/camera/image_raw` и `/camera/camera_info`;
- импорт калибровки из стандартного YAML;
- `camera_slam_preflight` для структурной проверки потока;
- `camera_feature_monitor` для проверки visual-feature качества;
- запись и воспроизведение reproducible bag-датасетов;
- сборку `experiment packet` по bag;
- backend runner для внешнего процесса;
- нормализацию trajectory в общий `trajectory_report.json`.

Для ORB-SLAM3 уже добавлены:

- `scripts/run_orbslam3_backend.ps1` — wrapper, который запускает backend, воспроизводит bag и собирает артефакты обратно в experiment packet;
- `config/slam_backend.orbslam3.template.json` — шаблон реальной конфигурации;
- `config/slam_backend.orbslam3.mock.template.json` — smoke-конфиг для локальной проверки;
- `scripts/new_orbslam3_backend_config.ps1` — генерация локального JSON-конфига из шаблона;
- `scripts/check_orbslam3_setup.ps1` — проверка путей и готовности setup;
- `scripts/orbslam3_backend_adapter_smoke_test.ps1` — end-to-end smoke-тест adapter layer.

## 2. Что этот репозиторий не устанавливает автоматически

`yoga_cam_sub` не приносит сам ORB-SLAM3 backend в underlay и не собирает его за вас.

Для реального запуска нужны внешние компоненты:

- executable или script, который реально запускает ORB-SLAM3 monocular pipeline;
- vocabulary файл `ORBvoc.txt`;
- settings YAML для ORB-SLAM3;
- рабочий каталог, в который backend сможет писать `CameraTrajectory.txt`;
- при необходимости bridge/launcher, который подписывается на ROS 2 топики и передаёт поток в ORB-SLAM3.

На текущей машине по состоянию на `2026-03-16` специализированный monocular SLAM backend не виден в активном underlay через `ros2 pkg list`, поэтому реальный runtime по-прежнему зависит от внешней установки.

## 3. Минимальные prerequisites перед интеграцией backend

### 3.1. Сборка workspace

```powershell
.\scripts\build_workspace.ps1
```

Если нужно сразу проверить весь software-only слой:

```powershell
.\scripts\run_tests.ps1
```

Если хочется прогнать и smoke-проверки:

```powershell
.\scripts\full_validation.ps1
```

### 3.2. Проверка камеры и топиков

Если backend позже будет работать от живой камеры, сначала подтвердите, что publisher вообще стабилен:

```powershell
.\scripts\run_camera_publisher.ps1 --ros-args -p device_index:=0 -p width:=640 -p height:=360 -p fps:=30.0
```

И в отдельном окне:

```cmd
scripts\run_in_ros_env.cmd ros2 topic list
scripts\run_in_ros_env.cmd ros2 topic echo --once /camera/image_raw
scripts\run_in_ros_env.cmd ros2 topic echo --once /camera/camera_info
```

Подробный ручной сценарий есть в `docs/manual_camera_verification.md`.

### 3.3. Импорт реальной калибровки

Если есть `ost.yaml` или другой стандартный YAML:

```powershell
.\scripts\import_camera_calibration.ps1 -SourceFile C:\path\to\ost.yaml
```

После этого полезно проверить поток уже с реальным `CameraInfo`:

```powershell
.\scripts\run_slam_preflight.ps1 calibration_file:=C:/dev/ros2_ws/src/yoga_cam_sub/config/camera_calibration.local.yaml
```

### 3.4. Подготовка эталонного dataset

Если хочется reproducible backend run, лучше работать не от живой камеры, а от bag:

```powershell
.\scripts\run_dataset_record.ps1 -DurationSeconds 10
```

Потом этот же bag можно воспроизвести без камеры:

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\path\to\bag -RunPreflight
```

### 3.5. Подготовка experiment packet

ORB-SLAM3 integration в этом репозитории строится именно поверх experiment workflow.

Сначала собираем packet:

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\path\to\bag
```

На выходе нужен каталог вида:

```text
artifacts/slam_experiments/<experiment_name>/
```

В нём уже будут:

- `experiment_manifest.json`
- `experiment_summary.md`
- `reports/preflight_report.json`
- `reports/feature_report.json`

## 4. Что должно лежать на машине для реального ORB-SLAM3 запуска

Для первого практического прогона подготовьте вне репозитория четыре вещи.

### 4.1. Backend command

Это основной исполняемый файл или wrapper-script, который:

- стартует ORB-SLAM3;
- умеет подписаться на ROS 2 топики;
- завершает работу после окончания bag playback или по внешнему сигналу.

Примеры:

- `C:\orbslam3\bin\orbslam3_ros2_bridge.exe`
- `C:\orbslam3\scripts\run_monocular_bridge.ps1`

### 4.2. Vocabulary

Нужен файл `ORBvoc.txt` или его эквивалент.

Пример:

```text
C:\orbslam3\Vocabulary\ORBvoc.txt
```

### 4.3. Settings YAML

Нужен конфиг, согласованный с вашей камерой и профилем bag:

- ширина и высота кадра;
- FPS;
- фокусные расстояния и principal point;
- коэффициенты дисторсии;
- ORB extractor параметры.

Пример:

```text
C:\orbslam3\config\yoga_cam_sub_monocular.yaml
```

### 4.4. Working directory

Нужен каталог, куда backend сможет писать runtime-output.

Пример:

```text
C:\orbslam3\runtime
```

Текущий wrapper ожидает, что trajectory-файл появится в рабочем каталоге под именем:

```text
CameraTrajectory.txt
```

Если имя другое, его можно задать через `orbslam3_trajectory_source` в config.

## 5. Рекомендуемая структура внешнего ORB-SLAM3 каталога

Это не обязательный стандарт, но с ним проще не запутаться:

```text
C:\orbslam3\
  bin\
    orbslam3_ros2_bridge.exe
  Vocabulary\
    ORBvoc.txt
  config\
    yoga_cam_sub_monocular.yaml
  runtime\
```

Если структура другая, это не проблема: runner всё равно работает по путям из JSON-конфига.

## 6. Как создать локальный config без ручного редактирования JSON

Для этого добавлен скрипт:

```powershell
.\scripts\new_orbslam3_backend_config.ps1 `
  -OutputFile config/slam_backend.orbslam3.local.json `
  -BackendCommand C:\orbslam3\bin\orbslam3_ros2_bridge.exe `
  -WorkingDirectory C:\orbslam3\runtime `
  -VocabularyPath C:\orbslam3\Vocabulary\ORBvoc.txt `
  -SettingsPath C:\orbslam3\config\yoga_cam_sub_monocular.yaml
```

Если backend не нужно запускать через `run_in_ros_env.cmd`, можно убрать этот слой:

```powershell
.\scripts\new_orbslam3_backend_config.ps1 `
  -OutputFile config/slam_backend.orbslam3.local.json `
  -BackendCommand C:\orbslam3\bin\orbslam3_ros2_bridge.exe `
  -WorkingDirectory C:\orbslam3\runtime `
  -VocabularyPath C:\orbslam3\Vocabulary\ORBvoc.txt `
  -SettingsPath C:\orbslam3\config\yoga_cam_sub_monocular.yaml `
  -WithoutRosEnv
```

Скрипт:

- берёт `config/slam_backend.orbslam3.template.json`;
- подставляет реальные пути;
- сохраняет локальный вариант в `config/slam_backend.orbslam3.local.json`.

## 7. Как проверить setup перед реальным запуском

Для этого есть отдельный preflight-скрипт:

```powershell
.\scripts\check_orbslam3_setup.ps1 `
  -ConfigFile config/slam_backend.orbslam3.local.json `
  -ExperimentPath C:\dev\ros2_ws\src\yoga_cam_sub\artifacts\slam_experiments\my_experiment `
  -CheckRosEnv
```

Скрипт проверяет:

- существует ли backend command;
- существует ли vocabulary;
- существует ли settings file;
- существует ли experiment packet;
- существует ли `metadata.yaml` у bag;
- виден ли `yoga_cam_sub` в `ros2 pkg list`, если передан `-CheckRosEnv`.

Если чего-то не хватает, скрипт завершается кодом `1` и печатает blocking issues.

## 8. Как проверить только adapter layer, не имея реального backend

Это первый обязательный шаг после изменения wrapper/config:

```powershell
.\scripts\orbslam3_backend_adapter_smoke_test.ps1
```

Smoke-тест проверяет:

- запуск ORB-SLAM3 wrapper;
- playback bag рядом с backend process;
- копирование `CameraTrajectory.txt` в experiment packet;
- разбор `tum_pose_v1`;
- построение `trajectory_report.json`;
- обновление manifest и catalog.

Если этот шаг не проходит, нет смысла переходить к реальному backend.

## 9. Как запустить реальный backend на готовом experiment packet

### 9.1. Сначала убедитесь, что packet уже есть

Если его ещё нет:

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\path\to\bag -ExperimentName baseline_room_daylight
```

### 9.2. Затем запускайте backend runner

```powershell
.\scripts\run_slam_backend.ps1 `
  -ExperimentPath C:\dev\ros2_ws\src\yoga_cam_sub\artifacts\slam_experiments\baseline_room_daylight `
  -ConfigFile config/slam_backend.orbslam3.local.json
```

Что происходит дальше:

1. runner читает `experiment_manifest.json`;
2. подставляет пути из `template_variables`;
3. запускает `scripts/run_orbslam3_backend.ps1`;
4. wrapper стартует ORB-SLAM3 backend;
5. wrapper воспроизводит bag через `ros2 bag play`;
6. wrapper ждёт trajectory в рабочем каталоге backend;
7. trajectory переносится в `backend_artifacts/orbslam3/`;
8. runner строит `reports/trajectory_report.json`;
9. manifest, summary и catalog обновляются.

## 10. Какие артефакты должны появиться после успешного прогона

Внутри experiment packet ожидаются:

```text
backend_artifacts/
  backend_stdout.log
  backend_stderr.log
  backend_result.json
  orbslam3/
    CameraTrajectory.txt
    orbslam3_runtime.log

reports/
  trajectory_report.json
  trajectory_report.md
```

В `experiment_manifest.json` должны обновиться:

- `backend_result.runner`
- `backend_result.artifacts`
- `backend_result.analysis.trajectory`

## 11. Как понять, что запуск действительно успешен

Минимальные признаки успеха:

- `run_slam_backend.ps1` завершился без exception;
- в manifest `backend_result.runner.success == true`;
- `backend_result.artifacts.trajectory_found == true`;
- `backend_result.analysis.trajectory.success == true`;
- `trajectory_report.json` содержит положительный `path_length_m`.

## 12. Самые типовые проблемы и что делать

### 12.1. Backend command не найден

Симптом:

- `check_orbslam3_setup.ps1` сообщает `Backend command was not found`.

Что делать:

- проверьте путь в `orbslam3_command`;
- если это relative path, убедитесь, что он резолвится от package root или workdir;
- лучше использовать абсолютный путь хотя бы на первом запуске.

### 12.2. ORBvoc.txt не найден

Симптом:

- setup-check падает на `vocabulary_path`.

Что делать:

- убедитесь, что vocabulary действительно существует;
- проверьте регистр имени файла;
- лучше хранить vocabulary отдельно от runtime каталога.

### 12.3. Settings YAML не найден

Симптом:

- setup-check падает на `settings_path`;
- backend быстро завершается с ошибкой.

Что делать:

- проверьте путь к YAML;
- проверьте, что YAML относится именно к текущему camera profile;
- не смешивайте настройки от другого разрешения или другой калибровки.

### 12.4. Backend стартует, но trajectory не появляется

Симптом:

- `backend_result.runner.exit_code == 0`, но `trajectory_found == false`.

Что делать:

- проверьте, куда именно backend пишет trajectory;
- при необходимости измените `orbslam3_trajectory_source`;
- проверьте, что у backend есть права на запись в workdir;
- откройте `backend_artifacts/orbslam3/orbslam3_runtime.log`.

### 12.5. trajectory появилась, но не разобралась

Симптом:

- `trajectory_found == true`, но `analysis.trajectory.success == false`.

Что делать:

- убедитесь, что trajectory действительно в формате `TUM`: `timestamp tx ty tz qx qy qz qw`;
- проверьте, нет ли заголовка в неожиданном формате;
- проверьте, что timestamp монотонны и что в файле больше одной позы.

### 12.6. ORB-SLAM3 нужно другое завершение процесса

Симптом:

- backend зависает после завершения playback;
- wrapper останавливает процесс принудительно.

Что делать:

- увеличьте `orbslam3_post_playback_grace_sec`;
- если backend завершает map dump дольше обычного, дайте ему больше времени;
- если нужен специальный shutdown-script, лучше обернуть backend отдельным вашим launcher и уже его указать в `orbslam3_command`.

## 13. Что стоит сделать прямо сейчас

Практический порядок без лишних скачков:

1. собрать workspace;
2. импортировать реальную калибровку;
3. записать один эталонный bag;
4. собрать experiment packet;
5. прогнать `orbslam3_backend_adapter_smoke_test.ps1`;
6. создать локальный config через `new_orbslam3_backend_config.ps1`;
7. проверить всё через `check_orbslam3_setup.ps1`;
8. только потом запускать реальный `run_slam_backend.ps1`.

## 14. Команды, которые чаще всего понадобятся

### Сборка

```powershell
.\scripts\build_workspace.ps1
```

### Полная software-only проверка

```powershell
.\scripts\full_validation.ps1
```

### Запись dataset

```powershell
.\scripts\run_dataset_record.ps1 -DurationSeconds 10
```

### Сборка experiment packet

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\path\to\bag
```

### Создание локального backend config

```powershell
.\scripts\new_orbslam3_backend_config.ps1 `
  -OutputFile config/slam_backend.orbslam3.local.json `
  -BackendCommand C:\orbslam3\bin\orbslam3_ros2_bridge.exe `
  -WorkingDirectory C:\orbslam3\runtime `
  -VocabularyPath C:\orbslam3\Vocabulary\ORBvoc.txt `
  -SettingsPath C:\orbslam3\config\yoga_cam_sub_monocular.yaml
```

### Проверка setup

```powershell
.\scripts\check_orbslam3_setup.ps1 `
  -ConfigFile config/slam_backend.orbslam3.local.json `
  -ExperimentPath C:\path\to\experiment `
  -CheckRosEnv
```

### Smoke adapter

```powershell
.\scripts\orbslam3_backend_adapter_smoke_test.ps1
```

### Реальный backend run

```powershell
.\scripts\run_slam_backend.ps1 `
  -ExperimentPath C:\path\to\experiment `
  -ConfigFile config/slam_backend.orbslam3.local.json
```
