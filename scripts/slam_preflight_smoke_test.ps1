[CmdletBinding()]
param(
  [string]$CalibrationFile = '',
  [int]$PublisherMaxFrames = 300,
  [int]$RequiredFrames = 15,
  [int]$MaxRuntimeSeconds = 25,
  [double]$MinFps = 5.0,
  [string]$FrameId = 'camera_optical_frame',
  [string]$ImageTopic = '/camera/image_raw',
  [string]$CameraInfoTopic = '/camera/camera_info'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$minFpsString = $MinFps.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture)

if ([string]::IsNullOrWhiteSpace($CalibrationFile)) {
  $localCalibration = Join-Path $packageRoot 'config\camera_calibration.local.yaml'
  if (Test-Path $localCalibration) {
    $CalibrationFile = $localCalibration.Replace('\', '/')
  }
}

$launchArguments = @(
  'ros2', 'launch', 'yoga_cam_sub', 'camera_slam_preflight.launch.py',
  "frame_id:=$FrameId",
  "image_topic:=$ImageTopic",
  "camera_info_topic:=$CameraInfoTopic",
  "publisher_max_frames:=$PublisherMaxFrames",
  "required_frames:=$RequiredFrames",
  "max_runtime_seconds:=$MaxRuntimeSeconds",
  "min_fps:=$minFpsString"
)
if (-not [string]::IsNullOrWhiteSpace($CalibrationFile)) {
  $launchArguments += "calibration_file:=$CalibrationFile"
}

Write-Host '[ИНФО] Запускаем smoke-проверку SLAM preflight через launch-сценарий.'
Write-Host ('[ИНФО] Launch: scripts\run_in_ros_env.cmd ' + ($launchArguments -join ' '))

& $envScript @launchArguments
if ($LASTEXITCODE -ne 0) {
  throw "SLAM preflight завершился с кодом $LASTEXITCODE."
}

Write-Host '[ИНФО] SLAM preflight smoke-тест завершён успешно.'
