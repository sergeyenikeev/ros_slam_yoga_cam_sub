[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BagPath,
  [string]$OutputFile = '',
  [double]$Rate = 1.0,
  [switch]$RunPreflight,
  [switch]$RunImageCounter,
  [int]$StartupDelaySeconds = 2,
  [int]$CounterMaxFrames = 1,
  [int]$RequiredFrames = 10,
  [int]$MaxRuntimeSeconds = 15,
  [double]$MinFps = 1.0,
  [string]$ImageTopic = '/camera/image_raw',
  [string]$CameraInfoTopic = '/camera/camera_info',
  [string]$ExpectedFrameId = 'camera_optical_frame'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$playbackScript = Join-Path $PSScriptRoot 'run_dataset_playback.ps1'
$datasetPlaybackRoot = Join-Path $packageRoot 'artifacts\dataset_playback'

. (Join-Path $PSScriptRoot 'dataset_catalog_utils.ps1')

if (-not $RunPreflight -and -not $RunImageCounter) {
  $RunPreflight = $true
}
if ($RunPreflight -and $RunImageCounter) {
  throw 'Одновременно можно строить отчёт либо по preflight, либо по image_counter.'
}

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
  $suffix = if ($RunPreflight) { 'preflight' } else { 'image_counter' }
  $OutputFile = Join-Path $reportsRoot ("dataset_report_${suffix}_" + (Get-Date -Format 'yyyyMMdd_HHmmss') + '.json')
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
  ImageTopic = $ImageTopic
  CameraInfoTopic = $CameraInfoTopic
  ExpectedFrameId = $ExpectedFrameId
}
if ($RunPreflight) {
  $playbackArguments.RunPreflight = $true
  $playbackArguments.RequiredFrames = $RequiredFrames
  $playbackArguments.MaxRuntimeSeconds = $MaxRuntimeSeconds
  $playbackArguments.MinFps = $MinFps
} else {
  $playbackArguments.RunImageCounter = $true
  $playbackArguments.CounterMaxFrames = $CounterMaxFrames
}

Write-Host '[ИНФО] Запускаем построение dataset report.'
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
    mode = if ($RunPreflight) { 'preflight' } else { 'image_counter' }
    startup_delay_seconds = $StartupDelaySeconds
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

if ($RunPreflight) {
  $summaryPattern = 'Preflight summary:\s+images=(\d+)\s+camera_infos=(\d+)\s+average_fps=([0-9\.]+)\s+mean_period_ms=([0-9\.]+)\s+min_period_ms=([0-9\.]+)\s+max_period_ms=([0-9\.]+)\s+stddev_period_ms=([0-9\.]+)\s+frame_id=([^\s]+)\s+encoding=([^\.\s]+)'
  $summaryMatch = [regex]::Match($combinedLogs, $summaryPattern)
  if (-not $summaryMatch.Success) {
    throw 'Не удалось извлечь строку Preflight summary из логов playback.'
  }

  $report['preflight'] = [ordered]@{
    success = $combinedLogs.Contains('SLAM preflight завершён успешно')
    images = [int]$summaryMatch.Groups[1].Value
    camera_infos = [int]$summaryMatch.Groups[2].Value
    average_fps = [double]::Parse($summaryMatch.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    mean_period_ms = [double]::Parse($summaryMatch.Groups[4].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    min_period_ms = [double]::Parse($summaryMatch.Groups[5].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    max_period_ms = [double]::Parse($summaryMatch.Groups[6].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    stddev_period_ms = [double]::Parse($summaryMatch.Groups[7].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    frame_id = $summaryMatch.Groups[8].Value
    encoding = $summaryMatch.Groups[9].Value
  }
} else {
  $counterMatch = [regex]::Match($combinedLogs, 'Получен кадр #([0-9]+)')
  $report['image_counter'] = [ordered]@{
    success = $combinedLogs.Contains('Достигнут лимит max_frames=')
    received_frames = if ($counterMatch.Success) { [int]$counterMatch.Groups[1].Value } else { 0 }
  }
}

Set-Content -Path $OutputFile -Value ($report | ConvertTo-Json -Depth 8) -Encoding UTF8
Write-Host '[ИНФО] Dataset report успешно сохранён.'
Write-Host "[ИНФО] report_path=$OutputFile"


