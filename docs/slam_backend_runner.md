# Backend Runner для monocular SLAM

Этот документ описывает слой интеграции внешнего SLAM backend в уже существующий workflow экспериментов.

## Зачем он нужен

До добавления backend runner experiment packet хранил только входные артефакты:

- preflight-report;
- feature-report;
- manifest;
- summary.

Теперь `run_slam_backend.ps1` умеет:

- взять готовый `experiment_manifest.json`;
- запустить внешний backend командой или скриптом;
- сохранить `stdout` и `stderr` backend в каталог эксперимента;
- проверить наличие trajectory / map / runtime-log;
- обновить manifest, summary и общий каталог экспериментов.

Это позволяет поэтапно готовить реальную интеграцию SLAM даже до установки конкретного backend в текущий Windows underlay.

## Основной сценарий

### 1. Сначала создаём experiment packet

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\путь\к\bag
```

### 2. Затем запускаем backend поверх этого эксперимента

```powershell
.\scripts\run_slam_backend.ps1 `
  -ExperimentPath C:\dev\ros2_ws\src\yoga_cam_sub\artifacts\slam_experiments\my_experiment `
  -ConfigFile config/slam_backend.mock.template.json
```

## Что появляется в experiment packet

После запуска backend в каталоге эксперимента появляются:

- `backend_artifacts/backend_stdout.log`
- `backend_artifacts/backend_stderr.log`
- `backend_artifacts/backend_result.json`
- trajectory / map / runtime-log, если backend их создал

Одновременно обновляются:

- `experiment_manifest.json`
- `experiment_summary.md`
- `artifacts/slam_experiments/slam_experiment_catalog.json`
- `artifacts/slam_experiments/slam_experiment_catalog.md`
- `artifacts/slam_experiments/slam_experiment_catalog.csv`

## Конфигурация backend runner

Пример конфигурации лежит в:

```text
config/slam_backend.mock.template.json
```

Поддерживаются поля:

- `backend_name`
- `command`
- `arguments`
- `working_directory`
- `timeout_seconds`
- `trajectory_path`
- `map_path`
- `runtime_log_path`
- `result_notes`
- `allow_failure`

В строковых полях можно использовать шаблоны:

- `{experiment_root}`
- `{experiment_name}`
- `{dataset_root}`
- `{dataset_name}`
- `{bag_root}`
- `{reports_root}`
- `{backend_root}`
- `{trajectory_path}`
- `{map_path}`
- `{runtime_log_path}`
- `{stdout_log_path}`
- `{stderr_log_path}`

## Auto-run backend из experiment config

Если в `config/slam_experiment.template.json` заполнить секцию `backend_runner` и установить:

```json
"auto_run": true
```

то backend можно запускать сразу вместе со сборкой experiment packet:

```powershell
.\scripts\run_slam_experiment.ps1 -BagPath C:\путь\к\bag -ConfigFile config\my_experiment.json
```

## Smoke-проверка

Для проверки backend runner без реального SLAM backend есть:

```powershell
.\scripts\slam_backend_runner_smoke_test.ps1
```

Smoke-сценарий использует `scripts/mock_slam_backend.ps1`, который создаёт фиктивные trajectory/map/runtime-артефакты и подтверждает, что orchestration, manifest и catalog обновляются корректно.
