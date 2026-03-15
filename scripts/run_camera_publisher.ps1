[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RosArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
. (Join-Path $PSScriptRoot 'process_utils.ps1')
$arguments = @('ros2', 'run', 'yoga_cam_sub', 'camera_publisher') + $RosArgs

Write-Host '[ИНФО] Запускаем camera_publisher.'
$result = Invoke-RosEnvCommand -EnvScript $envScript -Arguments $arguments -PrintOutput -AllowNonZeroExit
exit $result.ExitCode
