[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BagPath,
  [string]$OutputFile = '',
  [double]$Rate = 1.0,
  [int]$StartupDelaySeconds = 2,
  [int]$RequiredFrames = 20,
  [int]$MaxRuntimeSeconds = 15,
  [int]$LogEveryNFrames = 10,
  [int]$SkipInitialFrames = 10,
  [int]$MaxFeatures = 500,
  [int]$GridRows = 4,
  [int]$GridCols = 4,
  [int]$MinAverageKeypoints = 150,
  [double]$MinAverageGridCoverageRatio = 0.35,
  [double]$MinAverageBlurScore = 80.0,
  [double]$MinAverageBrightnessMean = 25.0,
  [string]$ImageTopic = '/camera/image_raw'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$playbackScript = Join-Path $PSScriptRoot 'run_dataset_playback.ps1'
$datasetPlaybackRoot = Join-Path $packageRoot 'artifacts\dataset_playback'

. (Join-Path $PSScriptRoot 'dataset_catalog_utils.ps1')

$resolvedBagPath = (Resolve-Path $BagPath).Path
$datasetRoot = Split-Path -Parent $resolvedBagPath
$manifestPath = Get-DatasetManifestPath -DatasetRoot $datasetRoot
$manifest = $null
if (Test-Path $manifestPath) {
  $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
  $reportsRoot = Join-Path $datasetRoot 'reports'
  New-Item -ItemType Directory -Force -Path $reportsRoot | Out-Null
  $OutputFile = Join-Path $reportsRoot ('dataset_feature_report_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
}
if (-not [System.IO.Path]::IsPathRooted($OutputFile)) {
  $OutputFile = Join-Path $packageRoot $OutputFile
}
$outputDirectory = Split-Path -Parent $OutputFile
if (-not (Test-Path $outputDirectory)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

$playbackArguments = @{
  BagPath = $resolvedBagPath
  Rate = $Rate
  StartupDelaySeconds = $StartupDelaySeconds
  RunFeatureMonitor = $true
  FeatureRequiredFrames = $RequiredFrames
  FeatureMaxRuntimeSeconds = $MaxRuntimeSeconds
  FeatureLogEveryNFrames = $LogEveryNFrames
  FeatureSkipInitialFrames = $SkipInitialFrames
  FeatureMaxFeatures = $MaxFeatures
  FeatureGridRows = $GridRows
  FeatureGridCols = $GridCols
  MinAverageKeypoints = $MinAverageKeypoints
  MinAverageGridCoverageRatio = $MinAverageGridCoverageRatio
  MinAverageBlurScore = $MinAverageBlurScore
  MinAverageBrightnessMean = $MinAverageBrightnessMean
  ImageTopic = $ImageTopic
}

Write-Host '[ИНФО] Запускаем построение feature-отчёта по датасету.'
Write-Host "[ИНФО] bag_path=$resolvedBagPath"
Write-Host "[ИНФО] output_file=$OutputFile"

& $playbackScript @playbackArguments

$subscriberStdout = Join-Path $datasetPlaybackRoot 'subscriber_stdout.log'
$subscriberStderr = Join-Path $datasetPlaybackRoot 'subscriber_stderr.log'
$combinedLogs = ''
if (Test-Path $subscriberStdout) {
  $combinedLogs += Get-Content $subscriberStdout -Raw -Encoding UTF8
}
if (Test-Path $subscriberStderr) {
  $combinedLogs += "`n" + (Get-Content $subscriberStderr -Raw -Encoding UTF8)
}

# Извлекаем summary из логов ноды, чтобы отчёт строился без отдельного
# протокола обмена и повторял реальный runtime-output узла.
$summaryPattern = 'Feature summary:\s+images=(\d+)\s+average_keypoints=([0-9\.]+)\s+min_keypoints=(\d+)\s+average_response=([0-9\.]+)\s+average_coverage=([0-9\.]+)\s+average_blur=([0-9\.]+)\s+average_brightness=([0-9\.]+)\s+average_contrast=([0-9\.]+)\s+frame_id=([^\s]+)\s+encoding=([^\.\s]+)'
$summaryMatch = [regex]::Match($combinedLogs, $summaryPattern)
if (-not $summaryMatch.Success) {
  throw 'Не удалось извлечь строку Feature summary из логов playback.'
}

$report = [ordered]@{
  schema_version = 1
  generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  dataset_name = if ($manifest) { $manifest.dataset_name } else { Split-Path $datasetRoot -Leaf }
  dataset_root = $datasetRoot
  bag_root = $resolvedBagPath
  manifest_path = if (Test-Path $manifestPath) { $manifestPath } else { '' }
  git = if ($manifest) {
    [ordered]@{
      branch = $manifest.git.branch
      commit = $manifest.git.commit
    }
  } else {
    Get-GitSnapshot -RepositoryRoot $packageRoot
  }
  playback = [ordered]@{
    rate = $Rate
    mode = 'feature_monitor'
    startup_delay_seconds = $StartupDelaySeconds
  }
  thresholds = [ordered]@{
    required_frames = $RequiredFrames
    max_runtime_seconds = $MaxRuntimeSeconds
    log_every_n_frames = $LogEveryNFrames
    skip_initial_frames = $SkipInitialFrames
    max_features = $MaxFeatures
    grid_rows = $GridRows
    grid_cols = $GridCols
    min_average_keypoints = $MinAverageKeypoints
    min_average_grid_coverage_ratio = $MinAverageGridCoverageRatio
    min_average_blur_score = $MinAverageBlurScore
    min_average_brightness_mean = $MinAverageBrightnessMean
  }
  feature_monitor = [ordered]@{
    success = $combinedLogs.Contains('Feature monitor завершён успешно')
    images = [int]$summaryMatch.Groups[1].Value
    average_keypoints = [double]::Parse($summaryMatch.Groups[2].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    min_keypoints = [int]$summaryMatch.Groups[3].Value
    average_response = [double]::Parse($summaryMatch.Groups[4].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    average_coverage = [double]::Parse($summaryMatch.Groups[5].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    average_blur = [double]::Parse($summaryMatch.Groups[6].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    average_brightness = [double]::Parse($summaryMatch.Groups[7].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    average_contrast = [double]::Parse($summaryMatch.Groups[8].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    frame_id = $summaryMatch.Groups[9].Value
    encoding = $summaryMatch.Groups[10].Value
  }
}

if ($manifest) {
  $report['recording'] = [ordered]@{
    width = $manifest.recording.width
    height = $manifest.recording.height
    fps = $manifest.recording.fps
    storage_id = $manifest.recording.storage_id
    use_msmf_selected = $manifest.recording.use_msmf_selected
    calibration_file = $manifest.recording.calibration_file
  }
  $report['rosbag'] = [ordered]@{
    duration_seconds = $manifest.rosbag.duration_seconds
    message_count_total = $manifest.rosbag.message_count_total
    topics = $manifest.rosbag.topics
  }
}

Set-Content -Path $OutputFile -Value ($report | ConvertTo-Json -Depth 8) -Encoding UTF8
Write-Host '[ИНФО] Feature-отчёт по датасету успешно сохранён.'
Write-Host "[ИНФО] report_path=$OutputFile"
