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
- effective config эксперимента.

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

## Как это использовать дальше

Следующий практический шаг — расширить experiment packet результатами реального backend:

- trajectory;
- pose graph / map output;
- runtime log;
- субъективные заметки по качеству трекинга;
- флаг `tracking_lost`.

То есть этот workflow уже можно считать каркасом для полноценного `SLAM experiment registry`.
