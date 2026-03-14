[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$checks = @(
  @{ Title = 'Путь к cl.exe'; Args = @('where', 'cl') },
  @{ Title = 'Путь к ninja.exe'; Args = @('where', 'ninja') },
  @{ Title = 'Путь к ros2'; Args = @('where', 'ros2') },
  @{ Title = 'Путь к colcon'; Args = @('where', 'colcon') },
  @{ Title = 'Версия CMake'; Args = @('cmake', '--version') },
  @{ Title = 'Проверка ROS-пакета yoga_cam_sub'; Args = @('cmd', '/c', 'ros2 pkg list | findstr yoga_cam_sub') }
)

foreach ($check in $checks) {
  Write-Host "`n=== $($check.Title) ==="
  & $envScript @($check.Args)
  if ($LASTEXITCODE -ne 0) {
    throw "Проверка '$($check.Title)' завершилась с кодом $LASTEXITCODE."
  }
}

Write-Host "`n[ИНФО] Диагностика окружения завершена успешно."
