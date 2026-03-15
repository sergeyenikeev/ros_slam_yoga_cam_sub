[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$LaunchArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
. (Join-Path $PSScriptRoot 'process_utils.ps1')
$arguments = @('ros2', 'launch', 'yoga_cam_sub', 'camera_pipeline.launch.py') + $LaunchArgs

Write-Host '[ИНФО] Запускаем launch camera_pipeline.launch.py.'
$result = Invoke-RosEnvCommand -EnvScript $envScript -Arguments $arguments -PrintOutput -AllowNonZeroExit
exit $result.ExitCode
