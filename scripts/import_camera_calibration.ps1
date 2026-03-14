[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$SourceFile,
  [string]$DestinationFile = '',
  [int]$TargetWidth = 0,
  [int]$TargetHeight = 0,
  [switch]$SkipCopy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Convert-ToRosPath([string]$PathValue) {
  return $PathValue.Replace('\', '/')
}

if ((($TargetWidth -eq 0) -and ($TargetHeight -ne 0)) -or
    (($TargetWidth -ne 0) -and ($TargetHeight -eq 0))) {
  throw 'Параметры TargetWidth и TargetHeight должны задаваться вместе.'
}

$resolvedSource = (Resolve-Path $SourceFile).Path
if ([string]::IsNullOrWhiteSpace($DestinationFile)) {
  $DestinationFile = Join-Path $packageRoot 'config\camera_calibration.local.yaml'
}

if ([System.IO.Path]::IsPathRooted($DestinationFile)) {
  $resolvedDestination = $DestinationFile
} else {
  $resolvedDestination = Join-Path $packageRoot $DestinationFile
}

$destinationDirectory = Split-Path -Parent $resolvedDestination
if (-not (Test-Path $destinationDirectory)) {
  New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
}

if (-not $SkipCopy) {
  Copy-Item -Path $resolvedSource -Destination $resolvedDestination -Force
  Write-Host "[ИНФО] Файл калибровки скопирован в $resolvedDestination"
} else {
  $resolvedDestination = $resolvedSource
  Write-Host '[ИНФО] Копирование пропущено, используется исходный файл калибровки.'
}

$rosCalibrationPath = Convert-ToRosPath $resolvedDestination
$arguments = @(
  'ros2', 'run', 'yoga_cam_sub', 'camera_calibration_inspector',
  '--ros-args',
  '-p', "calibration_file:=$rosCalibrationPath"
)
if ($TargetWidth -gt 0 -and $TargetHeight -gt 0) {
  $arguments += @('-p', "target_width:=$TargetWidth", '-p', "target_height:=$TargetHeight")
}

Write-Host '[ИНФО] Проверяем импортированный YAML калибровки.'
& $envScript @arguments
if ($LASTEXITCODE -ne 0) {
  throw 'camera_calibration_inspector сообщил об ошибке в файле калибровки.'
}

Write-Host '[ИНФО] Файл калибровки валиден.'
Write-Host '[ИНФО] Примеры следующего запуска:'
Write-Host ('.\scripts\run_camera_publisher.ps1 --ros-args -p calibration_file:=' + $rosCalibrationPath)
Write-Host ('.\scripts\run_slam_ready_pipeline.ps1 calibration_file:=' + $rosCalibrationPath)
