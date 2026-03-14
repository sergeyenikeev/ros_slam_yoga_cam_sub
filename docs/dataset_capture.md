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
- одновременно поднимать `camera_slam_preflight`.

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

## Автоматический smoke-тест

```powershell
.\scripts\dataset_bag_smoke_test.ps1
```

Smoke-тест:

1. пишет короткий bag с реальной камеры;
2. проверяет наличие `metadata.yaml`;
3. воспроизводит bag в `camera_slam_preflight`;
4. завершает прогон ошибкой, если запись или воспроизведение не прошли.

## Что смотреть в результате

После записи проверьте:

- что в bag есть `metadata.yaml`;
- что `ros2 bag info` показывает `/camera/image_raw`, `/camera/camera_info` и `/tf_static`;
- что в логе playback/preflight есть summary по FPS и сообщения о корректном завершении.

## Рекомендации для следующих SLAM-шагов

- записывайте bag уже после импорта реальной калибровки;
- держите отдельный эталонный датасет для каждого важного разрешения/FPS;
- перед сравнением SLAM-настроек воспроизводите один и тот же bag, а не живую камеру.
