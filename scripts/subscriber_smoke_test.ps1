[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\smoke_tests'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$stdoutFile = Join-Path $artifactRoot 'image_counter_stdout.log'
$stderrFile = Join-Path $artifactRoot 'image_counter_stderr.log'
Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue

Write-Host '[ИНФО] Запускаем image_counter для smoke-теста.'
$process = Start-Process `
  -FilePath $envScript `
  -ArgumentList @('ros2', 'run', 'yoga_cam_sub', 'image_counter', '--ros-args', '-p', 'image_topic:=/camera/image_raw', '-p', 'max_frames:=1') `
  -RedirectStandardOutput $stdoutFile `
  -RedirectStandardError $stderrFile `
  -PassThru

try {
  Start-Sleep -Seconds 3

  Write-Host '[ИНФО] Публикуем тестовое сообщение в /camera/image_raw.'
  & $envScript ros2 topic pub --once /camera/image_raw sensor_msgs/msg/Image "{header: {frame_id: 'test_camera'}, height: 1, width: 1, encoding: 'bgr8', is_bigendian: 0, step: 3, data: [1, 2, 3]}"
  if ($LASTEXITCODE -ne 0) {
    throw 'Не удалось опубликовать тестовое сообщение.'
  }

  if (-not $process.WaitForExit(20000)) {
    throw 'image_counter не завершился после получения тестового сообщения.'
  }

  $stdout = if (Test-Path $stdoutFile) { Get-Content $stdoutFile -Raw } else { '' }
  $stderr = if (Test-Path $stderrFile) { Get-Content $stderrFile -Raw } else { '' }
  $combinedOutput = $stdout + "`n" + $stderr
  if ($combinedOutput -notmatch 'frame_id=test_camera width=1 height=1 encoding=bgr8 step=3') {
    throw "Smoke-тест не подтвердил обработку кадра. Лог: $stderrFile"
  }

  Write-Host '[ИНФО] Smoke-тест image_counter завершён успешно.'
}
finally {
  if (-not $process.HasExited) {
    Stop-Process -Id $process.Id -Force
  }
}
