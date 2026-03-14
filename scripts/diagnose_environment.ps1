[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$checks = @(
  @{ Title = 'Поиск cl.exe'; Args = @('where', 'cl') },
  @{ Title = 'Поиск ninja.exe'; Args = @('where', 'ninja') },
  @{ Title = 'Поиск ros2'; Args = @('where', 'ros2') },
  @{ Title = 'Поиск colcon'; Args = @('where', 'colcon') },
  @{ Title = 'Версия CMake'; Args = @('cmake', '--version') },
  @{ Title = 'Список ROS-пакетов с yoga_cam_sub'; Args = @('cmd', '/c', 'ros2 pkg list | findstr yoga_cam_sub') }
)

foreach ($check in $checks) {
  Write-Host "`n=== $($check.Title) ==="
  & $envScript @($check.Args)
  if ($LASTEXITCODE -ne 0) {
    throw "Проверка '$($check.Title)' завершилась с кодом $LASTEXITCODE."
  }
}

Write-Host "`n[ИНФО] Диагностика завершена успешно."
