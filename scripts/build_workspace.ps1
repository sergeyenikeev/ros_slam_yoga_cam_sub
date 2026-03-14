[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$arguments = @(
  'colcon', 'build',
  '--merge-install',
  '--packages-select', 'yoga_cam_sub',
  '--cmake-clean-cache',
  '--cmake-force-configure',
  '--event-handlers', 'console_cohesion+',
  '--cmake-args', '-GNinja', '-DCMAKE_BUILD_TYPE=Release'
) + $ExtraArgs

Write-Host '[ИНФО] Запускаем сборку workspace для yoga_cam_sub.'
& $envScript @arguments
exit $LASTEXITCODE
