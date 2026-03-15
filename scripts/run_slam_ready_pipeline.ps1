[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$LaunchArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
. (Join-Path $PSScriptRoot 'process_utils.ps1')
$arguments = @('ros2', 'launch', 'yoga_cam_sub', 'camera_slam_ready.launch.py') + $LaunchArgs

Write-Host '[ИНФО] Запускаем SLAM-ready pipeline с камерой и статическим TF.'
$result = Invoke-RosEnvCommand -EnvScript $envScript -Arguments $arguments -PrintOutput -AllowNonZeroExit
exit $result.ExitCode
