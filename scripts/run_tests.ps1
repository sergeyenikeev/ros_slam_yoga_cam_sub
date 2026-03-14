[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$staleLintResult = Join-Path $workspaceRoot 'build\yoga_cam_sub\test_results\yoga_cam_sub\uncrustify.xunit.xml'
if (Test-Path $staleLintResult) {
  $deleteCommand = "del /f /q `"$staleLintResult`""
  cmd.exe /c $deleteCommand | Out-Null
}

Write-Host '[ИНФО] Запускаем набор тестов yoga_cam_sub.'
& $envScript colcon test --merge-install --packages-select yoga_cam_sub --event-handlers console_cohesion+
if ($LASTEXITCODE -ne 0) {
  exit $LASTEXITCODE
}

& $envScript colcon test-result --verbose --test-result-base build\yoga_cam_sub
exit $LASTEXITCODE
