# Workflow экспериментов monocular SLAM

Этот документ описывает новый слой automation между recorded bag и будущим реальным SLAM backend.

## Зачем нужен experiment workflow

Когда bag уже записан, у нас возникает следующая проблема: нужно не просто воспроизводить его, а хранить весь контекст конкретного эксперимента в одном месте.

`run_slam_experiment.ps1` решает именно это.

Он собирает:

- preflight-report по dataset;
- feature-report по dataset;
- experiment manifest;
- markdown summary;
- effective config эксперимента;
- шаблонные поля для ручной оценки backend;
- автоматическое обновление общего каталога экспериментов.

Теперь следующий слой тоже уже подготовлен: отдельный backend runner умеет запускать внешний SLAM backend поверх готового experiment packet.
Если backend сохраняет trajectory в формате `csv_pose_v1` или `tum_pose_v1`, workflow автоматически строит отдельный trajectory-report и включает его в manifest.
Для feature-report шаблонный конфиг дополнительно пропускает первые 10 кадров bag как прогревочные, чтобы автоэкспозиция ноутбучной камеры не делала smoke-прогоны флак.

Это делает дальнейшую интеграцию реального SLAM backend воспроизводимой.

## Быстрый запуск

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\путь\к\bag
```

По умолчанию experiment packet будет сохранён в:

```text
artifacts/slam_experiments/slam_experiment_<timestamp>/
```

## Запуск с конфигурационным шаблоном

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\путь\к\bag -ConfigFile config/slam_experiment.template.json -ExperimentName baseline_room_daylight
```

## Что появляется в каталоге эксперимента

- `experiment_manifest.json` — главный machine-readable итог;
- `experiment_summary.md` — краткая human-readable сводка;
- `reports/preflight_report.json` — структурная пригодность потока;
- `reports/feature_report.json` — visual-feature пригодность потока.

После каждого запуска также обновляется общий файл:

- `artifacts/slam_experiments/slam_experiment_catalog.json`

Он нужен, чтобы быстро увидеть все накопленные experiment packet и их ключевые метрики.

## Что означает `ready_for_slam`

Поле `experiment.ready_for_slam` в manifest становится `true`, если:

- preflight-report успешен;
- feature-report успешен.

То есть bag уже прошёл две независимые проверки:

1. структура и timing потока;
2. качество visual-feature в кадре.

Это ещё не означает, что внешний SLAM backend точно заработает идеально, но означает, что входной набор данных уже инженерно подготовлен к запуску.

## Smoke-проверка workflow

```powershell
.\scripts\slam_experiment_smoke_test.ps1
```

Скрипт использует последний доступный dataset, собирает experiment packet и проверяет наличие всех ключевых файлов.

## Offline-сравнение двух экспериментов

Когда появляется baseline и новый кандидат, можно сравнить их без запуска камеры:

```powershell
.\scripts\compare_slam_experiments.ps1 `
  -BaselineExperiment C:\путь\к\baseline_experiment `
  -CandidateExperiment C:\путь\к\candidate_experiment
```

На выходе появятся:

- `comparison.json` — machine-readable сравнение;
- `comparison_summary.md` — краткая human-readable сводка.

Сравнение сейчас работает по входным данным эксперимента:

- `ready_for_slam`;
- `average_fps`;
- `average_keypoints`;
- `average_coverage`;
- `average_blur`;
- `average_brightness`;
- ручная оценка `tracking_lost` и `map_quality`, если она уже заполнена.

Если оба эксперимента уже имеют trajectory-report от backend runner, comparison дополнительно включает:

- `trajectory_sample_count`;
- `trajectory_duration_sec`;
- `trajectory_path_length_m`;
- `trajectory_net_displacement_m`;
- `trajectory_mean_speed_mps`;
- `trajectory_max_step_m`.

Для быстрой проверки есть отдельный smoke-тест:

```powershell
.\scripts\slam_experiment_compare_smoke_test.ps1
```

## Запуск внешнего backend поверх эксперимента

Если experiment packet уже собран, можно отдельно запустить backend:

```powershell
.\scripts\run_slam_backend.ps1 `
  -ExperimentPath C:\путь\к\experiment `
  -ConfigFile config/slam_backend.mock.template.json
```

После запуска обновляются:

- `backend_artifacts/backend_stdout.log`
- `backend_artifacts/backend_stderr.log`
- `backend_artifacts/backend_result.json`
- `reports/trajectory_report.json`
- `reports/trajectory_report.md`
- `experiment_manifest.json`
- `experiment_summary.md`
- общий реестр экспериментов в JSON/Markdown/CSV

Для первого реального monocular backend теперь уже подготовлен пилотный adapter layer под ORB-SLAM3:

```powershell
.\scripts\run_slam_backend.ps1 `
  -ExperimentPath C:\путь\к\experiment `
  -ConfigFile config/slam_backend.orbslam3.template.json
```

## Как это использовать дальше

Следующий практический шаг — расширить experiment packet результатами реального backend:

- trajectory;
- pose graph / map output;
- runtime log;
- субъективные заметки по качеству трекинга;
- флаг `tracking_lost`.

Часть этого шага уже закрыта:

- есть `run_slam_backend.ps1` для запуска внешнего backend;
- есть `mock_slam_backend.ps1` и smoke-проверка orchestration;
- есть автоматический trajectory-report и offline-сравнение trajectory-метрик;
- есть пилотный ORB-SLAM3 adapter layer с отдельным smoke-тестом и поддержкой `tum_pose_v1`;
- каталог экспериментов теперь экспортируется не только в JSON, но и в Markdown/CSV.

То есть этот workflow уже можно считать каркасом для полноценного `SLAM experiment registry`.
