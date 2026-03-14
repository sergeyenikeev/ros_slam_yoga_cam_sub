[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$LaunchArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$arguments = @('ros2', 'launch', 'yoga_cam_sub', 'camera_slam_preflight.launch.py') + $LaunchArgs

Write-Host '[ИНФО] Запускаем SLAM preflight для проверки потока камеры.'
& $envScript @arguments
exit $LASTEXITCODE
