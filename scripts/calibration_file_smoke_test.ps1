[CmdletBinding()]
param(
  [int]$TargetWidth = 1280,
  [int]$TargetHeight = 720
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sampleFile = Join-Path $packageRoot 'config\camera_calibration.sample.yaml'

if (-not (Test-Path $sampleFile)) {
  throw "Пример файла калибровки не найден: $sampleFile"
}
if ($TargetWidth -le 0 -or $TargetHeight -le 0) {
  throw 'TargetWidth и TargetHeight должны быть положительными.'
}

$rosCalibrationPath = $sampleFile.Replace('\', '/')

Write-Host '[ИНФО] Проверяем sample YAML калибровки через camera_calibration_inspector.'
& $envScript `
  ros2 run yoga_cam_sub camera_calibration_inspector `
  --ros-args `
  -p "calibration_file:=$rosCalibrationPath" `
  -p "target_width:=$TargetWidth" `
  -p "target_height:=$TargetHeight"
if ($LASTEXITCODE -ne 0) {
  throw "Проверка sample YAML завершилась с кодом $LASTEXITCODE."
}
