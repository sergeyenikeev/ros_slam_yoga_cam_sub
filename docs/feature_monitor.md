# Feature-мониторинг потока перед monocular SLAM

`camera_feature_monitor` нужен как быстрый инженерный фильтр между "камера вроде работает" и "этот поток действительно стоит отдавать в monocular SLAM".

## Что проверяет узел

Узел подписывается на `/camera/image_raw` и по каждому кадру считает:

- число ORB-feature;
- средний отклик keypoint;
- покрытие кадра feature-сеткой;
- резкость кадра через дисперсию лапласиана;
- среднюю яркость и контраст.

Эти метрики помогают быстро поймать типовые проблемы:

- камера смотрит в почти пустую стену;
- картинка смазана из-за движения или расфокуса;
- света слишком мало;
- feature сосредоточены только в одном участке кадра.

## Быстрый запуск на живой камере

```powershell
.\scripts\run_feature_monitor.ps1 publisher_max_frames:=60 required_frames:=10
```

По умолчанию launch поднимает `camera_publisher` и `camera_feature_monitor` в одном сценарии.

## Полезные параметры

- `required_frames` — сколько кадров собрать до итоговой оценки;
- `skip_initial_frames` — сколько первых кадров пропустить как прогревочные;
- `max_runtime_seconds` — максимальное время ожидания;
- `max_features` — лимит ORB-feature на кадр;
- `grid_rows`, `grid_cols` — сетка покрытия кадра;
- `min_average_keypoints` — минимальное среднее число keypoints;
- `min_average_grid_coverage_ratio` — минимальное среднее покрытие кадра feature-сеткой;
- `min_average_blur_score` — минимальная средняя резкость;
- `min_average_brightness_mean` — минимальная средняя яркость.

## Пример для более мягкой первичной проверки

```powershell
.\scripts\run_feature_monitor.ps1 publisher_max_frames:=60 required_frames:=10 min_average_keypoints:=80 min_average_grid_coverage_ratio:=0.20 min_average_blur_score:=20.0 min_average_brightness_mean:=15.0
```

Это полезно для smoke-проверок, когда нужно подтвердить сам pipeline без слишком строгих quality gate.

## Offline-проверка по rosbag

Если живая камера не нужна, используйте уже записанный bag:

```powershell
.\scripts\run_dataset_playback.ps1 -BagPath C:\путь\к\bag -RunFeatureMonitor -FeatureRequiredFrames 10 -FeatureSkipInitialFrames 10
```

Или сразу сохраните отдельный JSON-отчёт:

```powershell
.\scripts\run_dataset_feature_report.ps1 -BagPath C:\путь\к\bag
```

По умолчанию offline feature-report пропускает первые 10 кадров. Это снижает флак при bag, записанном с ноутбучной камеры, когда автоэкспозиция и баланс белого ещё стабилизируются в самом начале записи.

## Как читать summary

Узел печатает строку вида:

```text
Feature summary: images=10 average_keypoints=472.80 min_keypoints=469 average_response=0.0001 average_coverage=0.56 average_blur=343.70 average_brightness=118.20 average_contrast=40.38 frame_id=camera_optical_frame encoding=bgr8.
```

На практике полезно ориентироваться так:

- `average_keypoints < 100` — сцена бедная на ориентиры, SLAM может терять трек;
- `average_coverage < 0.25` — feature скучены в одной зоне кадра;
- `average_blur` заметно падает между прогонами — стоит проверить фокус, движение камеры или экспозицию;
- `average_brightness < 20` — обычно света уже мало для стабильного трекинга.

Это не универсальные истины для любого SLAM-пакета, а инженерные стартовые пороги для ноутбучной monocular камеры.

## Рекомендуемый порядок перед интеграцией SLAM

1. Импортировать реальную калибровку.
2. Прогнать `run_slam_preflight.ps1`.
3. Прогнать `run_feature_monitor.ps1`.
4. Записать эталонный bag через `run_dataset_record.ps1`.
5. Сохранить `run_dataset_report.ps1` и `run_dataset_feature_report.ps1` рядом с датасетом.
6. Только после этого подключать следующий monocular SLAM-узел.
