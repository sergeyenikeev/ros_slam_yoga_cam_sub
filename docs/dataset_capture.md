# Запись и воспроизведение датасета

Этот документ описывает workflow для записи коротких rosbag-датасетов из `yoga_cam_sub` и их последующего воспроизведения без живой камеры.

## Зачем это нужно

Rosbag-датасет полезен в трёх сценариях:

- повторяемая отладка visual SLAM без доступа к ноутбучной камере;
- сравнение разных настроек SLAM на одном и том же входе;
- хранение эталонных последовательностей после успешной калибровки.

## Что записывается

Скрипт `run_dataset_record.ps1` пишет в bag следующие топики:

- `/camera/image_raw`
- `/camera/camera_info`
- `/tf_static`

Этого достаточно, чтобы потом воспроизвести поток камеры и базовую TF-структуру для большинства monocular SLAM-прогонов.

## Быстрая запись

```powershell
.\scripts\run_dataset_record.ps1 -DurationSeconds 5
```

По умолчанию скрипт:

- запускает `camera_slam_ready.launch.py`;
- при наличии использует `config/camera_calibration.local.yaml`;
- записывает bag через storage `sqlite3`, который на Windows надёжнее переносит остановку записи и последующий `ros2 bag reindex`;
- записывает bag в `artifacts/datasets/camera_dataset_<timestamp>/bag`;
- сохраняет `dataset_manifest.json` с параметрами захвата, bag summary и git-коммитом;
- обновляет общий `artifacts/datasets/dataset_catalog.json`;
- после окончания автоматически печатает `ros2 bag info`.

## Полезные параметры записи

- `DurationSeconds` — сколько секунд писать bag;
- `DatasetName` — явное имя каталога датасета;
- `OutputRoot` — корневой каталог для сохранения bag;
- `CalibrationFile` — путь к YAML-калибровке;
- `DeviceIndex`, `Width`, `Height`, `Fps`, `UseMsmf` — параметры источника камеры;
- `StorageId` — backend rosbag (`sqlite3` по умолчанию, `mcap` доступен как опция).

## Почему по умолчанию выбран `sqlite3`

На Windows сценарий записи останавливает `ros2 bag record` по таймеру, а затем вызывает `ros2 bag reindex`.
Для `sqlite3` после такого завершения сохраняется корректный порядок сообщений при последующем `ros2 bag play`, поэтому dataset smoke-тест и `camera_slam_preflight` проходят стабильно.

`mcap` тоже поддерживается, но после принудительной остановки может воспроизводиться в порядке файла без полноценного message index. Если нужен именно `mcap`, после записи обязательно прогоняйте `run_dataset_playback.ps1 -RunPreflight` и проверяйте временные метки.

## Быстрое воспроизведение

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\dev\ros2_ws\src\yoga_cam_sub\artifacts\datasets\camera_dataset_YYYYMMDD_HHMMSS\bag -RunPreflight
```

Скрипт может:

- просто воспроизводить bag;
- одновременно поднимать `image_counter`;
- одновременно поднимать `camera_slam_preflight`;
- одновременно поднимать `camera_feature_monitor`.

## Варианты воспроизведения

### 1. Проверить, что изображения вообще читаются из bag

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunImageCounter -CounterMaxFrames 1
```

### 2. Проверить bag как вход для SLAM

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunPreflight -RequiredFrames 10 -MinFps 1.0
```

### 3. Замедлить или ускорить проигрывание

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunPreflight -Rate 0.5
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunPreflight -Rate 2.0
```

### 4. Проверить, достаточно ли visual-feature в recorded bag

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunFeatureMonitor -FeatureRequiredFrames 10
```

## Автоматический smoke-тест

```powershell
.\scripts\dataset_bag_smoke_test.ps1
```

Smoke-тест:

1. пишет короткий bag с реальной камеры;
2. проверяет наличие `metadata.yaml`;
3. проверяет наличие `dataset_manifest.json` и `dataset_catalog.json`;
4. воспроизводит bag в `camera_slam_preflight`;
5. строит итоговый JSON-report по датасету;
6. строит отдельный JSON-report по feature-качеству датасета;
7. завершает прогон ошибкой, если запись или воспроизведение не прошли.

## Манифест датасета

После записи рядом с bag появляется `dataset_manifest.json`. Он нужен, чтобы офлайн-прогоны были воспроизводимыми даже через несколько дней:

- хранит параметры камеры и выбранный backend OpenCV;
- сохраняет bag summary и counts по топикам;
- фиксирует git-ветку и commit, на котором был записан датасет;
- даёт единый JSON-источник для дальнейших SLAM-экспериментов и отчётов.

## Общий каталог датасетов

Чтобы быстро просмотреть все записанные bag, используйте:

```powershell
.\scripts\update_dataset_catalog.ps1
```

Скрипт пересобирает `artifacts/datasets/dataset_catalog.json` и печатает краткую таблицу по доступным датасетам.

## Offline report по датасету

Если нужно сохранить отдельный report по offline playback/preflight, используйте:

```powershell
.\scripts\run_dataset_report.ps1 -BagPath C:\путь\к\bag
```

Скрипт повторно воспроизводит bag, извлекает summary из `camera_slam_preflight` и записывает JSON-отчёт в каталог `reports/` рядом с датасетом.

## Offline feature-report по датасету

Если нужно отдельно оценить качество visual-feature для будущего SLAM, используйте:

```powershell
.\scripts\run_dataset_feature_report.ps1 -BagPath C:\путь\к\bag
```

Скрипт повторно воспроизводит bag, извлекает `Feature summary` из `camera_feature_monitor` и записывает JSON-отчёт в каталог `reports/` рядом с датасетом.

В этом отчёте полезно смотреть на:

- `average_keypoints` — среднее число ORB-feature на кадр;
- `average_coverage` — насколько feature распределены по площади кадра;
- `average_blur` — не слишком ли картинка смазана;
- `average_brightness` и `average_contrast` — хватает ли света и текстуры.

## Полный пакет эксперимента по датасету

Когда bag уже прошёл preflight и feature-check, следующий логичный шаг — собрать единый пакет эксперимента:

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\путь\к\bag
```

Скрипт создаёт отдельный каталог в `artifacts/slam_experiments/` и складывает туда:

- `experiment_manifest.json`;
- `experiment_summary.md`;
- preflight-report;
- feature-report.

Это удобно как точка входа для будущего реального SLAM backend и сравнения нескольких прогонов на одном bag.

## Что смотреть в результате

После записи проверьте:

- что в bag есть `metadata.yaml`;
- что `ros2 bag info` показывает `/camera/image_raw`, `/camera/camera_info` и `/tf_static`;
- что в логе playback/preflight есть summary по FPS и сообщения о корректном завершении.

## Рекомендации для следующих SLAM-шагов

- записывайте bag уже после импорта реальной калибровки;
- держите отдельный эталонный датасет для каждого важного разрешения/FPS;
- перед сравнением SLAM-настроек воспроизводите один и тот же bag, а не живую камеру.
