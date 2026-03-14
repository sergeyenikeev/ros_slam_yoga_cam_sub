[CmdletBinding()]
param(
  [int]$PublisherMaxFrames = 10,
  [int]$CounterMaxFrames = 1,
  [int]$TimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\launch_smoke_test'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$stdoutFile = Join-Path $artifactRoot 'camera_pipeline_stdout.log'
$stderrFile = Join-Path $artifactRoot 'camera_pipeline_stderr.log'
Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue

Write-Host '[ИНФО] Запускаем launch smoke-тест camera_pipeline.launch.py.'
$process = Start-Process `
  -FilePath $envScript `
  -ArgumentList @(
    'ros2', 'launch', 'yoga_cam_sub', 'camera_pipeline.launch.py',
    "publisher_max_frames:=$PublisherMaxFrames",
    "counter_max_frames:=$CounterMaxFrames"
  ) `
  -RedirectStandardOutput $stdoutFile `
  -RedirectStandardError $stderrFile `
  -PassThru

try {
  if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
    throw "Launch smoke-тест не завершился за $TimeoutSeconds секунд."
  }

  $process.WaitForExit()
  $process.Refresh()
  $exitCode = $null
  try {
    $exitCode = $process.ExitCode
  }
  catch {
    $exitCode = $null
  }

  $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { '' }
  $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { '' }
  $combined = $stdout + "`n" + $stderr

  if (($null -ne $exitCode) -and ($exitCode -ne 0)) {
    throw "Launch smoke-тест завершился с кодом $exitCode. Логи: $stdoutFile и $stderrFile"
  }
  if (-not $combined.Contains('frame_id=camera_optical_frame width=640 height=360 encoding=bgr8')) {
    throw "Launch smoke-тест не подтвердил получение кадра узлом image_counter. Лог: $stdoutFile"
  }
  if (-not $combined.Contains('process has finished cleanly')) {
    throw "Launch smoke-тест не подтвердил штатное завершение процессов. Лог: $stdoutFile"
  }

  Write-Host '[ИНФО] Launch smoke-тест завершён успешно.'
}
finally {
  if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
