[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$baseArguments = @(
  'colcon', 'build',
  '--merge-install',
  '--packages-select', 'yoga_cam_sub',
  '--cmake-clean-cache',
  '--cmake-force-configure',
  '--event-handlers', 'console_cohesion+',
  '--cmake-args', '-GNinja', '-DCMAKE_BUILD_TYPE=Release'
)
$extraArguments = @($ExtraArgs | Where-Object { $null -ne $_ -and $_ -ne '' })
$arguments = $baseArguments + $extraArguments

Write-Host '[ИНФО] Запускаем сборку workspace для yoga_cam_sub.'
$stdoutPath = Join-Path $env:TEMP ('yoga_cam_sub_build_' + [System.Guid]::NewGuid().ToString('N') + '.stdout.log')
$stderrPath = Join-Path $env:TEMP ('yoga_cam_sub_build_' + [System.Guid]::NewGuid().ToString('N') + '.stderr.log')

try {
  # Запускаем wrapper через Start-Process и отдельно собираем stdout/stderr,
  # чтобы предупреждения ROS 2 в stderr не превращались в ошибки PowerShell.
  $process = Start-Process `
    -FilePath $envScript `
    -ArgumentList $arguments `
    -NoNewWindow `
    -Wait `
    -PassThru `
    -RedirectStandardOutput $stdoutPath `
    -RedirectStandardError $stderrPath

  if (Test-Path $stdoutPath) {
    Get-Content -Path $stdoutPath | Write-Host
  }
  if (Test-Path $stderrPath) {
    Get-Content -Path $stderrPath | Write-Host
  }

  if ($process.ExitCode -ne 0) {
    throw "Сборка workspace завершилась с кодом $($process.ExitCode)."
  }
}
finally {
  Remove-Item -Path $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
}
