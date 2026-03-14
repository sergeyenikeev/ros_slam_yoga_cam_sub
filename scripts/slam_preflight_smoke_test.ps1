[CmdletBinding()]
param(
  [string]$CalibrationFile = '',
  [int]$PublisherMaxFrames = 300,
  [int]$RequiredFrames = 15,
  [int]$MaxRuntimeSeconds = 25,
  [int]$PublisherStartupDelaySeconds = 4,
  [double]$MinFps = 5.0,
  [string]$FrameId = 'camera_optical_frame',
  [string]$ImageTopic = '/camera/image_raw',
  [string]$CameraInfoTopic = '/camera/camera_info'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\slam_preflight'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$publisherStdout = Join-Path $artifactRoot 'camera_publisher_stdout.log'
$publisherStderr = Join-Path $artifactRoot 'camera_publisher_stderr.log'
Remove-Item $publisherStdout, $publisherStderr -ErrorAction SilentlyContinue

$minFpsString = $MinFps.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture)
if ([string]::IsNullOrWhiteSpace($CalibrationFile)) {
  $localCalibration = Join-Path $packageRoot 'config\camera_calibration.local.yaml'
  if (Test-Path $localCalibration) {
    $CalibrationFile = $localCalibration.Replace('\', '/')
  }
}

$publisherArguments = @(
  'ros2', 'run', 'yoga_cam_sub', 'camera_publisher',
  '--ros-args',
  '-p', "frame_id:=$FrameId",
  '-p', "image_topic:=$ImageTopic",
  '-p', "camera_info_topic:=$CameraInfoTopic",
  '-p', "max_frames:=$PublisherMaxFrames"
)
if (-not [string]::IsNullOrWhiteSpace($CalibrationFile)) {
  $publisherArguments += @('-p', "calibration_file:=$CalibrationFile")
}

$preflightArguments = @(
  'ros2', 'run', 'yoga_cam_sub', 'camera_slam_preflight',
  '--ros-args',
  '-p', "image_topic:=$ImageTopic",
  '-p', "camera_info_topic:=$CameraInfoTopic",
  '-p', "expected_frame_id:=$FrameId",
  '-p', "required_frames:=$RequiredFrames",
  '-p', "max_runtime_seconds:=$MaxRuntimeSeconds",
  '-p', "min_fps:=$minFpsString"
)

Write-Host '[ИНФО] Запускаем smoke-проверку SLAM preflight.'
Write-Host ('[ИНФО] Publisher: scripts\run_in_ros_env.cmd ' + ($publisherArguments -join ' '))
Write-Host ('[ИНФО] Preflight: scripts\run_in_ros_env.cmd ' + ($preflightArguments -join ' '))

$publisherProcess = $null

try {
  $publisherProcess = Start-Process `
    -FilePath $envScript `
    -ArgumentList $publisherArguments `
    -RedirectStandardOutput $publisherStdout `
    -RedirectStandardError $publisherStderr `
    -PassThru

  Start-Sleep -Seconds $PublisherStartupDelaySeconds

  & $envScript @preflightArguments
  $preflightExitCode = $LASTEXITCODE

  if ($preflightExitCode -ne 0) {
    Write-Host '[ИНФО] Логи camera_publisher для диагностики:'
    Get-Content $publisherStderr -Encoding UTF8 | Write-Host
    throw "SLAM preflight завершился с кодом $preflightExitCode."
  }

  Write-Host '[ИНФО] SLAM preflight smoke-тест завершён успешно.'
}
finally {
  if ($publisherProcess -and -not $publisherProcess.HasExited) {
    Stop-Process -Id $publisherProcess.Id -Force
  }
}
