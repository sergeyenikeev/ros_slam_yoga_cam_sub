Set-StrictMode -Version Latest

function Get-SlamExperimentManifestPath {
  param([string]$ExperimentRoot)

  return Join-Path $ExperimentRoot 'experiment_manifest.json'
}

function Get-SlamExperimentSummaryPath {
  param([string]$ExperimentRoot)

  return Join-Path $ExperimentRoot 'experiment_summary.md'
}

function Get-SlamExperimentCatalogPath {
  param([string]$ExperimentsRoot)

  return Join-Path $ExperimentsRoot 'slam_experiment_catalog.json'
}

function Get-SlamExperimentCatalogMarkdownPath {
  param([string]$ExperimentsRoot)

  return Join-Path $ExperimentsRoot 'slam_experiment_catalog.md'
}

function Get-SlamExperimentCatalogCsvPath {
  param([string]$ExperimentsRoot)

  return Join-Path $ExperimentsRoot 'slam_experiment_catalog.csv'
}

function Get-ObjectValue {
  param(
    $Object,
    [string[]]$PathSegments,
    $DefaultValue = $null
  )

  $current = $Object
  foreach ($segment in $PathSegments) {
    if ($null -eq $current) {
      return $DefaultValue
    }

    $property = $current.PSObject.Properties[$segment]
    if (-not $property) {
      return $DefaultValue
    }

    $current = $property.Value
  }

  if ($null -eq $current) {
    return $DefaultValue
  }
  if ($current -is [string] -and [string]::IsNullOrWhiteSpace($current)) {
    return $DefaultValue
  }

  return $current
}

function Resolve-SlamExperimentManifestPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'Путь до эксперимента пустой.'
  }

  $resolvedPath = (Resolve-Path $Path).Path
  $item = Get-Item -LiteralPath $resolvedPath
  if ($item.PSIsContainer) {
    $manifestPath = Get-SlamExperimentManifestPath -ExperimentRoot $item.FullName
    if (-not (Test-Path $manifestPath)) {
      throw "В каталоге эксперимента не найден experiment_manifest.json: $($item.FullName)"
    }
    return $manifestPath
  }

  if ($item.Extension -ne '.json') {
    throw "Ожидался JSON-манифест или каталог эксперимента, но получен файл: $($item.FullName)"
  }

  return $item.FullName
}

function Read-SlamExperimentManifest {
  param([string]$Path)

  $manifestPath = Resolve-SlamExperimentManifestPath -Path $Path
  return Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Save-SlamExperimentManifest {
  param(
    [object]$Manifest,
    [string]$ManifestPath
  )

  Set-Content -Path $ManifestPath -Value ($Manifest | ConvertTo-Json -Depth 12) -Encoding UTF8
}

function Get-ExperimentTrackingLostLabel {
  param($Value)

  if ($null -eq $Value) {
    return 'не_оценено'
  }
  if ([bool]$Value) {
    return 'да'
  }

  return 'нет'
}

function Resolve-ExperimentArtifactPath {
  param(
    [string]$ExperimentRoot,
    [string]$PathValue
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return ''
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }

  return Join-Path $ExperimentRoot $PathValue
}

function Write-SlamExperimentSummary {
  param(
    [object]$Manifest,
    [string]$SummaryPath
  )

  $effectiveNotes = [string](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'notes') -DefaultValue '')
  $manualTrackingLost = Get-ObjectValue -Object $Manifest -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null
  $manualMapQuality = [string](Get-ObjectValue -Object $Manifest -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
  $manualSubjectiveNotes = [string](Get-ObjectValue -Object $Manifest -PathSegments @('manual_assessment', 'subjective_notes') -DefaultValue '')
  $backendTrajectoryPath = [string](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'trajectory_path') -DefaultValue '')
  $backendMapPath = [string](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'map_path') -DefaultValue '')
  $backendRuntimeLogPath = [string](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runtime_log_path') -DefaultValue '')
  $backendResultNotes = [string](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'result_notes') -DefaultValue '')
  $backendExecutionSuccess = Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'success') -DefaultValue $null
  $backendExitCode = Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'exit_code') -DefaultValue $null
  $backendTimedOut = Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'timed_out') -DefaultValue $null
  $backendStdoutLog = [string](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'stdout_log_path') -DefaultValue '')
  $backendStderrLog = [string](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'stderr_log_path') -DefaultValue '')
  $trajectoryFound = Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'artifacts', 'trajectory_found') -DefaultValue $false
  $mapFound = Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'artifacts', 'map_found') -DefaultValue $false
  $runtimeLogFound = Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'artifacts', 'runtime_log_found') -DefaultValue $false
  $preflightReportPath = [string](Get-ObjectValue -Object $Manifest -PathSegments @('checks', 'preflight_report_path') -DefaultValue '')
  $featureReportPath = [string](Get-ObjectValue -Object $Manifest -PathSegments @('checks', 'feature_report_path') -DefaultValue '')
  $backendRunLabel = if ($null -eq $backendExecutionSuccess) {
    '<не запускался>'
  } else {
    [string]$backendExecutionSuccess
  }
  $backendExitLabel = if ($null -eq $backendExitCode) {
    '<не запускался>'
  } else {
    [string]$backendExitCode
  }

  $summaryLines = @(
    '# Пакет эксперимента monocular SLAM',
    '',
    "- experiment_name: $($Manifest.experiment_name)",
    "- dataset_name: $($Manifest.dataset_name)",
    "- slam_backend: $([string](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан'))",
    "- ready_for_slam: $([bool](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false))",
    "- bag_root: $($Manifest.bag_root)",
    "- preflight_report: $(if ([string]::IsNullOrWhiteSpace($preflightReportPath)) { '<пропущен>' } else { $preflightReportPath })",
    "- feature_report: $(if ([string]::IsNullOrWhiteSpace($featureReportPath)) { '<пропущен>' } else { $featureReportPath })"
  )

  if (-not [string]::IsNullOrWhiteSpace($effectiveNotes)) {
    $summaryLines += @('', '## Заметки', '', $effectiveNotes)
  }

  $summaryLines += @(
    '',
    '## Поля для фиксации результата backend',
    '',
    "- tracking_lost: $(Get-ExperimentTrackingLostLabel -Value $manualTrackingLost)",
    "- map_quality: $manualMapQuality",
    "- trajectory_path: $(if ([string]::IsNullOrWhiteSpace($backendTrajectoryPath)) { '<не заполнено>' } else { $backendTrajectoryPath })",
    "- map_path: $(if ([string]::IsNullOrWhiteSpace($backendMapPath)) { '<не заполнено>' } else { $backendMapPath })",
    "- runtime_log_path: $(if ([string]::IsNullOrWhiteSpace($backendRuntimeLogPath)) { '<не заполнено>' } else { $backendRuntimeLogPath })"
  )

  if (-not [string]::IsNullOrWhiteSpace($manualSubjectiveNotes)) {
    $summaryLines += @('', '## Субъективные заметки по backend', '', $manualSubjectiveNotes)
  }
  if (-not [string]::IsNullOrWhiteSpace($backendResultNotes)) {
    $summaryLines += @('', '## Заметки по артефактам backend', '', $backendResultNotes)
  }

  $summaryLines += @(
    '',
    '## Выполнение backend',
    '',
    "- backend_run_success: $backendRunLabel",
    "- backend_exit_code: $backendExitLabel",
    "- backend_timed_out: $(if ($null -eq $backendTimedOut) { '<не запускался>' } else { [string]$backendTimedOut })",
    "- backend_stdout_log: $(if ([string]::IsNullOrWhiteSpace($backendStdoutLog)) { '<не заполнено>' } else { $backendStdoutLog })",
    "- backend_stderr_log: $(if ([string]::IsNullOrWhiteSpace($backendStderrLog)) { '<не заполнено>' } else { $backendStderrLog })",
    "- trajectory_found: $trajectoryFound",
    "- map_found: $mapFound",
    "- runtime_log_found: $runtimeLogFound"
  )

  $summaryLines += @('', '## Следующие шаги', '')
  if ([bool](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false)) {
    if ($backendExecutionSuccess -eq $true) {
      $summaryLines += '- Входные проверки и запуск backend прошли успешно: можно сравнивать trajectory, map и качество трекинга с baseline.'
    } else {
      $summaryLines += '- Пакет эксперимента готов: можно запускать внешний monocular SLAM backend и сохранять его output в этот же каталог.'
    }
  } else {
    $summaryLines += '- Пакет эксперимента пока не готов к SLAM: сначала разберите preflight/feature-отчёты и улучшите поток.'
  }

  Set-Content -Path $SummaryPath -Value ($summaryLines -join "`r`n") -Encoding UTF8
}

function ConvertTo-SlamExperimentCatalogEntry {
  param([object]$Manifest)

  return [pscustomobject][ordered]@{
    experiment_name = $Manifest.experiment_name
    generated_at_utc = $Manifest.generated_at_utc
    dataset_name = $Manifest.dataset_name
    slam_backend = [string](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан')
    ready_for_slam = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false)
    preflight_success = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('preflight', 'success') -DefaultValue $false)
    feature_success = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'success') -DefaultValue $false)
    average_fps = [double](Get-ObjectValue -Object $Manifest -PathSegments @('preflight', 'average_fps') -DefaultValue 0.0)
    average_keypoints = [double](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'average_keypoints') -DefaultValue 0.0)
    average_coverage = [double](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'average_coverage') -DefaultValue 0.0)
    average_blur = [double](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'average_blur') -DefaultValue 0.0)
    tracking_lost = Get-ObjectValue -Object $Manifest -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null
    map_quality = [string](Get-ObjectValue -Object $Manifest -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
    backend_ran = $null -ne (Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'started_at_utc') -DefaultValue $null)
    backend_success = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'success') -DefaultValue $false)
    backend_exit_code = Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'runner', 'exit_code') -DefaultValue $null
    trajectory_found = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'artifacts', 'trajectory_found') -DefaultValue $false)
    map_found = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'artifacts', 'map_found') -DefaultValue $false)
    runtime_log_found = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('backend_result', 'artifacts', 'runtime_log_found') -DefaultValue $false)
    experiment_root = $Manifest.experiment_root
    manifest_path = Get-SlamExperimentManifestPath -ExperimentRoot $Manifest.experiment_root
  }
}

function Export-SlamExperimentCatalogTables {
  param(
    [object]$Catalog,
    [string]$ExperimentsRoot
  )

  $markdownPath = Get-SlamExperimentCatalogMarkdownPath -ExperimentsRoot $ExperimentsRoot
  $csvPath = Get-SlamExperimentCatalogCsvPath -ExperimentsRoot $ExperimentsRoot
  $rows = @($Catalog.experiments)

  $markdownLines = @(
    '# Реестр экспериментов monocular SLAM',
    '',
    "- generated_at_utc: $($Catalog.generated_at_utc)",
    "- experiment_count: $($Catalog.experiment_count)",
    '',
    '| experiment_name | dataset_name | backend | ready | backend_success | avg_fps | avg_keypoints | map_quality | tracking_lost |',
    '| --- | --- | --- | --- | --- | --- | --- | --- | --- |'
  )
  foreach ($row in $rows) {
    $trackingLostLabel = Get-ExperimentTrackingLostLabel -Value $row.tracking_lost
    $markdownLines += "| $($row.experiment_name) | $($row.dataset_name) | $($row.slam_backend) | $($row.ready_for_slam) | $($row.backend_success) | $($row.average_fps) | $($row.average_keypoints) | $($row.map_quality) | $trackingLostLabel |"
  }
  Set-Content -Path $markdownPath -Value ($markdownLines -join "`r`n") -Encoding UTF8

  $csvRows = $rows | Select-Object `
    experiment_name,
    dataset_name,
    slam_backend,
    ready_for_slam,
    backend_success,
    backend_exit_code,
    average_fps,
    average_keypoints,
    average_coverage,
    average_blur,
    map_quality,
    tracking_lost,
    trajectory_found,
    map_found,
    runtime_log_found,
    experiment_root,
    manifest_path
  $csvRows | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

  return [pscustomobject]@{
    MarkdownPath = $markdownPath
    CsvPath = $csvPath
  }
}

function Update-SlamExperimentCatalogFile {
  param([string]$ExperimentsRoot)

  $catalogPath = Get-SlamExperimentCatalogPath -ExperimentsRoot $ExperimentsRoot
  $entries = @()

  if (-not (Test-Path $ExperimentsRoot)) {
    New-Item -ItemType Directory -Force -Path $ExperimentsRoot | Out-Null
    $catalog = [ordered]@{
      schema_version = 1
      generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
      experiment_count = 0
      experiments = @()
    }
    Set-Content -Path $catalogPath -Value ($catalog | ConvertTo-Json -Depth 6) -Encoding UTF8
    Export-SlamExperimentCatalogTables -Catalog $catalog -ExperimentsRoot $ExperimentsRoot | Out-Null
    return $catalog
  }

  foreach ($experimentDirectory in (Get-ChildItem -Path $ExperimentsRoot -Directory | Sort-Object Name)) {
    $manifestPath = Get-SlamExperimentManifestPath -ExperimentRoot $experimentDirectory.FullName
    if (-not (Test-Path $manifestPath)) {
      continue
    }

    $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries += ConvertTo-SlamExperimentCatalogEntry -Manifest $manifest
  }

  $orderedEntries = @($entries | Sort-Object generated_at_utc -Descending)
  $catalog = [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    experiment_count = $orderedEntries.Count
    experiments = $orderedEntries
  }

  Set-Content -Path $catalogPath -Value ($catalog | ConvertTo-Json -Depth 6) -Encoding UTF8
  Export-SlamExperimentCatalogTables -Catalog $catalog -ExperimentsRoot $ExperimentsRoot | Out-Null
  return $catalog
}

function Get-MetricDelta {
  param(
    $BaselineValue,
    $CandidateValue,
    [int]$Precision = 2
  )

  if ($null -eq $BaselineValue -or $null -eq $CandidateValue) {
    return $null
  }

  try {
    return [Math]::Round(([double]$CandidateValue - [double]$BaselineValue), $Precision)
  }
  catch {
    return $null
  }
}

function New-MetricComparison {
  param(
    [string]$MetricName,
    $BaselineValue,
    $CandidateValue,
    [int]$Precision = 2
  )

  return [ordered]@{
    name = $MetricName
    baseline = $BaselineValue
    candidate = $CandidateValue
    delta = Get-MetricDelta -BaselineValue $BaselineValue -CandidateValue $CandidateValue -Precision $Precision
  }
}

function Compare-SlamExperimentManifests {
  param(
    [object]$BaselineManifest,
    [object]$CandidateManifest,
    [string]$BaselineManifestPath,
    [string]$CandidateManifestPath
  )

  $sameDataset = $BaselineManifest.dataset_name -eq $CandidateManifest.dataset_name
  $baselineReady = [bool](Get-ObjectValue -Object $BaselineManifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false)
  $candidateReady = [bool](Get-ObjectValue -Object $CandidateManifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false)
  $baselineBackendSuccess = Get-ObjectValue -Object $BaselineManifest -PathSegments @('backend_result', 'runner', 'success') -DefaultValue $null
  $candidateBackendSuccess = Get-ObjectValue -Object $CandidateManifest -PathSegments @('backend_result', 'runner', 'success') -DefaultValue $null
  $baselineTrackingLost = Get-ObjectValue -Object $BaselineManifest -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null
  $candidateTrackingLost = Get-ObjectValue -Object $CandidateManifest -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null

  $notes = @()
  if (-not $sameDataset) {
    $notes += 'Сравниваются эксперименты на разных датасетах, поэтому дельты метрик нужно трактовать осторожно.'
  }
  if ($baselineReady -and -not $candidateReady) {
    $notes += 'У кандидата наблюдается регрессия готовности к SLAM относительно baseline.'
  }
  if (-not $baselineReady -and $candidateReady) {
    $notes += 'Кандидат улучшил статус ready_for_slam относительно baseline.'
  }
  if ($baselineBackendSuccess -eq $true -and $candidateBackendSuccess -eq $false) {
    $notes += 'У кандидата наблюдается регрессия выполнения backend относительно baseline.'
  }
  if ($baselineTrackingLost -eq $false -and $candidateTrackingLost -eq $true) {
    $notes += 'Кандидат потерял трекинг там, где baseline ещё удерживал его.'
  }
  if ($notes.Count -eq 0) {
    $notes += 'Критичных регрессий на уровне входных и backend-метрик не обнаружено; сравните trajectory и карту вручную.'
  }

  return [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    baseline = [ordered]@{
      experiment_name = $BaselineManifest.experiment_name
      dataset_name = $BaselineManifest.dataset_name
      slam_backend = [string](Get-ObjectValue -Object $BaselineManifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан')
      manifest_path = $BaselineManifestPath
      experiment_root = $BaselineManifest.experiment_root
    }
    candidate = [ordered]@{
      experiment_name = $CandidateManifest.experiment_name
      dataset_name = $CandidateManifest.dataset_name
      slam_backend = [string](Get-ObjectValue -Object $CandidateManifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан')
      manifest_path = $CandidateManifestPath
      experiment_root = $CandidateManifest.experiment_root
    }
    compatibility = [ordered]@{
      same_dataset = $sameDataset
      same_bag_root = $BaselineManifest.bag_root -eq $CandidateManifest.bag_root
    }
    readiness = [ordered]@{
      baseline_ready_for_slam = $baselineReady
      candidate_ready_for_slam = $candidateReady
      ready_for_slam_regressed = $baselineReady -and -not $candidateReady
      ready_for_slam_improved = (-not $baselineReady) -and $candidateReady
    }
    metrics = [ordered]@{
      average_fps = New-MetricComparison `
        -MetricName 'average_fps' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('preflight', 'average_fps') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('preflight', 'average_fps') -DefaultValue $null)
      average_keypoints = New-MetricComparison `
        -MetricName 'average_keypoints' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_keypoints') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_keypoints') -DefaultValue $null)
      average_coverage = New-MetricComparison `
        -MetricName 'average_coverage' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_coverage') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_coverage') -DefaultValue $null)
      average_blur = New-MetricComparison `
        -MetricName 'average_blur' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_blur') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_blur') -DefaultValue $null)
      average_brightness = New-MetricComparison `
        -MetricName 'average_brightness' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_brightness') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_brightness') -DefaultValue $null)
    }
    backend = [ordered]@{
      baseline_success = $baselineBackendSuccess
      candidate_success = $candidateBackendSuccess
      baseline_exit_code = Get-ObjectValue -Object $BaselineManifest -PathSegments @('backend_result', 'runner', 'exit_code') -DefaultValue $null
      candidate_exit_code = Get-ObjectValue -Object $CandidateManifest -PathSegments @('backend_result', 'runner', 'exit_code') -DefaultValue $null
      baseline_trajectory_found = [bool](Get-ObjectValue -Object $BaselineManifest -PathSegments @('backend_result', 'artifacts', 'trajectory_found') -DefaultValue $false)
      candidate_trajectory_found = [bool](Get-ObjectValue -Object $CandidateManifest -PathSegments @('backend_result', 'artifacts', 'trajectory_found') -DefaultValue $false)
      baseline_map_found = [bool](Get-ObjectValue -Object $BaselineManifest -PathSegments @('backend_result', 'artifacts', 'map_found') -DefaultValue $false)
      candidate_map_found = [bool](Get-ObjectValue -Object $CandidateManifest -PathSegments @('backend_result', 'artifacts', 'map_found') -DefaultValue $false)
    }
    manual_assessment = [ordered]@{
      baseline_tracking_lost = $baselineTrackingLost
      candidate_tracking_lost = $candidateTrackingLost
      baseline_map_quality = [string](Get-ObjectValue -Object $BaselineManifest -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
      candidate_map_quality = [string](Get-ObjectValue -Object $CandidateManifest -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
      baseline_subjective_notes = [string](Get-ObjectValue -Object $BaselineManifest -PathSegments @('manual_assessment', 'subjective_notes') -DefaultValue '')
      candidate_subjective_notes = [string](Get-ObjectValue -Object $CandidateManifest -PathSegments @('manual_assessment', 'subjective_notes') -DefaultValue '')
    }
    notes = $notes
  }
}
