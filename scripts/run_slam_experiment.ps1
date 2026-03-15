[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BagPath,
  [string]$ExperimentName = '',
  [string]$OutputRoot = '',
  [string]$ConfigFile = '',
  [string]$SlamBackend = '',
  [string]$Notes = '',
  [switch]$RunBackend,
  [switch]$SkipPreflightReport,
  [switch]$SkipFeatureReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'dataset_catalog_utils.ps1')
. (Join-Path $PSScriptRoot 'slam_experiment_utils.ps1')

function Get-ConfigValue {
  param(
    $Config,
    [string[]]$PathSegments,
    $DefaultValue
  )

  $current = $Config
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

$resolvedBagPath = (Resolve-Path $BagPath).Path
$datasetRoot = Split-Path -Parent $resolvedBagPath
$manifestPath = Get-DatasetManifestPath -DatasetRoot $datasetRoot
$datasetManifest = $null
if (Test-Path $manifestPath) {
  $datasetManifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$config = $null
if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
  $resolvedConfigPath = if ([System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile
  } else {
    Join-Path $packageRoot $ConfigFile
  }
  if (-not (Test-Path $resolvedConfigPath)) {
    throw "Файл конфигурации эксперимента не найден: $resolvedConfigPath"
  }
  $config = Get-Content -Path $resolvedConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ([string]::IsNullOrWhiteSpace($ExperimentName)) {
  $ExperimentName = Get-ConfigValue -Config $config -PathSegments @('experiment_name') -DefaultValue ''
}
if ([string]::IsNullOrWhiteSpace($ExperimentName)) {
  $ExperimentName = 'slam_experiment_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $packageRoot 'artifacts\slam_experiments'
}
if (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot = Join-Path $packageRoot $OutputRoot
}
$experimentRoot = Join-Path $OutputRoot $ExperimentName
if (Test-Path $experimentRoot) {
  throw "Каталог эксперимента уже существует: $experimentRoot"
}
$reportsRoot = Join-Path $experimentRoot 'reports'
New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null

$playbackRate = [double](Get-ConfigValue -Config $config -PathSegments @('playback', 'rate') -DefaultValue 1.0)
$preflightRequiredFrames = [int](Get-ConfigValue -Config $config -PathSegments @('preflight', 'required_frames') -DefaultValue 10)
$preflightMaxRuntimeSeconds = [int](Get-ConfigValue -Config $config -PathSegments @('preflight', 'max_runtime_seconds') -DefaultValue 15)
$preflightMinFps = [double](Get-ConfigValue -Config $config -PathSegments @('preflight', 'min_fps') -DefaultValue 1.0)
$featureRequiredFrames = [int](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'required_frames') -DefaultValue 10)
$featureMaxRuntimeSeconds = [int](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'max_runtime_seconds') -DefaultValue 15)
$featureLogEveryNFrames = [int](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'log_every_n_frames') -DefaultValue 10)
$featureMaxFeatures = [int](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'max_features') -DefaultValue 500)
$featureGridRows = [int](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'grid_rows') -DefaultValue 4)
$featureGridCols = [int](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'grid_cols') -DefaultValue 4)
$minAverageKeypoints = [int](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'min_average_keypoints') -DefaultValue 150)
$minAverageGridCoverageRatio = [double](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'min_average_grid_coverage_ratio') -DefaultValue 0.35)
$minAverageBlurScore = [double](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'min_average_blur_score') -DefaultValue 80.0)
$minAverageBrightnessMean = [double](Get-ConfigValue -Config $config -PathSegments @('feature_monitor', 'min_average_brightness_mean') -DefaultValue 25.0)

$effectiveSlamBackend = if (-not [string]::IsNullOrWhiteSpace($SlamBackend)) {
  $SlamBackend
} else {
  [string](Get-ConfigValue -Config $config -PathSegments @('slam_backend') -DefaultValue 'не_задан')
}
$effectiveNotes = if (-not [string]::IsNullOrWhiteSpace($Notes)) {
  $Notes
} else {
  [string](Get-ConfigValue -Config $config -PathSegments @('notes') -DefaultValue '')
}
$manualTrackingLost = Get-ConfigValue -Config $config -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null
$manualMapQuality = [string](Get-ConfigValue -Config $config -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
$manualSubjectiveNotes = [string](Get-ConfigValue -Config $config -PathSegments @('manual_assessment', 'subjective_notes') -DefaultValue '')
$backendTrajectoryPath = [string](Get-ConfigValue -Config $config -PathSegments @('backend_result', 'trajectory_path') -DefaultValue '')
$backendMapPath = [string](Get-ConfigValue -Config $config -PathSegments @('backend_result', 'map_path') -DefaultValue '')
$backendRuntimeLogPath = [string](Get-ConfigValue -Config $config -PathSegments @('backend_result', 'runtime_log_path') -DefaultValue '')
$backendResultNotes = [string](Get-ConfigValue -Config $config -PathSegments @('backend_result', 'result_notes') -DefaultValue '')
$shouldRunBackend = $RunBackend.IsPresent -or [bool](Get-ConfigValue -Config $config -PathSegments @('backend_runner', 'auto_run') -DefaultValue $false)

$preflightReportPath = Join-Path $reportsRoot 'preflight_report.json'
$featureReportPath = Join-Path $reportsRoot 'feature_report.json'
$manifestOutputPath = Join-Path $experimentRoot 'experiment_manifest.json'
$summaryOutputPath = Join-Path $experimentRoot 'experiment_summary.md'

Write-Host '[ИНФО] Подготавливаем пакет эксперимента monocular SLAM.'
Write-Host "[ИНФО] experiment_root=$experimentRoot"
Write-Host "[ИНФО] bag_path=$resolvedBagPath"
Write-Host "[ИНФО] slam_backend=$effectiveSlamBackend"

$preflightReport = $null
$featureReport = $null

if (-not $SkipPreflightReport) {
  # Перед любым SLAM-прогоном сначала подтверждаем, что поток синхронен,
  # имеет адекватный FPS и проходит базовые ROS-проверки.
  & (Join-Path $PSScriptRoot 'run_dataset_report.ps1') `
    -BagPath $resolvedBagPath `
    -Rate $playbackRate `
    -RequiredFrames $preflightRequiredFrames `
    -MaxRuntimeSeconds $preflightMaxRuntimeSeconds `
    -MinFps $preflightMinFps `
    -OutputFile $preflightReportPath

  $preflightReport = Get-Content -Path $preflightReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if (-not $SkipFeatureReport) {
  # Отдельно оцениваем visual-feature качество bag, чтобы не начинать SLAM
  # на потоке с бедной текстурой, смазом или плохим освещением.
  & (Join-Path $PSScriptRoot 'run_dataset_feature_report.ps1') `
    -BagPath $resolvedBagPath `
    -Rate $playbackRate `
    -RequiredFrames $featureRequiredFrames `
    -MaxRuntimeSeconds $featureMaxRuntimeSeconds `
    -LogEveryNFrames $featureLogEveryNFrames `
    -MaxFeatures $featureMaxFeatures `
    -GridRows $featureGridRows `
    -GridCols $featureGridCols `
    -MinAverageKeypoints $minAverageKeypoints `
    -MinAverageGridCoverageRatio $minAverageGridCoverageRatio `
    -MinAverageBlurScore $minAverageBlurScore `
    -MinAverageBrightnessMean $minAverageBrightnessMean `
    -OutputFile $featureReportPath

  $featureReport = Get-Content -Path $featureReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$readyForSlam = $true
if ($preflightReport -and -not $preflightReport.preflight.success) {
  $readyForSlam = $false
}
if ($featureReport -and -not $featureReport.feature_monitor.success) {
  $readyForSlam = $false
}

$experimentManifest = [ordered]@{
  schema_version = 1
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  experiment_name = $ExperimentName
  experiment_root = $experimentRoot
  dataset_name = if ($datasetManifest) { $datasetManifest.dataset_name } else { Split-Path $datasetRoot -Leaf }
  dataset_root = $datasetRoot
  bag_root = $resolvedBagPath
  manifest_path = if (Test-Path $manifestPath) { $manifestPath } else { '' }
  git = Get-GitSnapshot -RepositoryRoot $packageRoot
  experiment = [ordered]@{
    slam_backend = $effectiveSlamBackend
    notes = $effectiveNotes
    ready_for_slam = $readyForSlam
    config_file = if ([string]::IsNullOrWhiteSpace($ConfigFile)) { '' } else { $ConfigFile }
  }
  playback = [ordered]@{
    rate = $playbackRate
  }
  checks = [ordered]@{
    preflight_report_path = if (Test-Path $preflightReportPath) { $preflightReportPath } else { '' }
    feature_report_path = if (Test-Path $featureReportPath) { $featureReportPath } else { '' }
  }
  manual_assessment = [ordered]@{
    tracking_lost = $manualTrackingLost
    map_quality = $manualMapQuality
    subjective_notes = $manualSubjectiveNotes
  }
  backend_result = [ordered]@{
    trajectory_path = $backendTrajectoryPath
    map_path = $backendMapPath
    runtime_log_path = $backendRuntimeLogPath
    result_notes = $backendResultNotes
  }
}

if ($datasetManifest) {
  $experimentManifest['recording'] = [ordered]@{
    width = $datasetManifest.recording.width
    height = $datasetManifest.recording.height
    fps = $datasetManifest.recording.fps
    storage_id = $datasetManifest.recording.storage_id
    use_msmf_selected = $datasetManifest.recording.use_msmf_selected
    calibration_file = $datasetManifest.recording.calibration_file
  }
}
if ($preflightReport) {
  $experimentManifest['preflight'] = $preflightReport.preflight
}
if ($featureReport) {
  $experimentManifest['feature_monitor'] = $featureReport.feature_monitor
}

Save-SlamExperimentManifest -Manifest $experimentManifest -ManifestPath $manifestOutputPath
Write-SlamExperimentSummary -Manifest $experimentManifest -SummaryPath $summaryOutputPath

# После каждой сборки пакета эксперимента обновляем сводный каталог, чтобы
# следующий шаг автоматизации сразу видел все доступные SLAM-прогоны.
$catalog = Update-SlamExperimentCatalogFile -ExperimentsRoot $OutputRoot
$catalogPath = Get-SlamExperimentCatalogPath -ExperimentsRoot $OutputRoot
$catalogMarkdownPath = Get-SlamExperimentCatalogMarkdownPath -ExperimentsRoot $OutputRoot
$catalogCsvPath = Get-SlamExperimentCatalogCsvPath -ExperimentsRoot $OutputRoot

Write-Host '[ИНФО] Пакет эксперимента monocular SLAM успешно подготовлен.'
Write-Host "[ИНФО] manifest_path=$manifestOutputPath"
Write-Host "[ИНФО] summary_path=$summaryOutputPath"
Write-Host "[ИНФО] catalog_path=$catalogPath"
Write-Host "[ИНФО] catalog_markdown_path=$catalogMarkdownPath"
Write-Host "[ИНФО] catalog_csv_path=$catalogCsvPath"

if ($shouldRunBackend) {
  Write-Host '[ИНФО] Конфигурация требует автоматически запустить внешний backend.'
  $backendArguments = @('-ExperimentPath', $experimentRoot)
  if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
    $backendArguments += @('-ConfigFile', $ConfigFile)
  }

  & (Join-Path $PSScriptRoot 'run_slam_backend.ps1') @backendArguments
}
