[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$LaunchArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$arguments = @('ros2', 'launch', 'yoga_cam_sub', 'camera_feature_monitor.launch.py') + $LaunchArgs

Write-Host '[ИНФО] Запускаем feature-мониторинг потока камеры.'
& $envScript @arguments
exit $LASTEXITCODE
