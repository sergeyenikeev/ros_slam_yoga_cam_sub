[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$RosArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$arguments = @('ros2', 'run', 'yoga_cam_sub', 'camera_publisher') + $RosArgs

Write-Host '[ИНФО] Запускается camera_publisher.'
& $envScript @arguments
exit $LASTEXITCODE
