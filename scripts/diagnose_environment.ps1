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

function Invoke-RosEnvCommand {
  param([string[]]$Arguments)

  $stdoutFile = [System.IO.Path]::GetTempFileName()
  $stderrFile = [System.IO.Path]::GetTempFileName()

  try {
    # Запускаем `.cmd` через отдельный процесс, чтобы штатно собрать stdout/stderr
    # и не падать на ожидаемых RTI warning в PowerShell-обёртках.
    $process = Start-Process `
      -FilePath $envScript `
      -ArgumentList $Arguments `
      -RedirectStandardOutput $stdoutFile `
      -RedirectStandardError $stderrFile `
      -PassThru `
      -Wait

    $outputChunks = @()
    if (Test-Path $stdoutFile) {
      $stdout = Get-Content $stdoutFile -Raw
      if (-not [string]::IsNullOrWhiteSpace($stdout)) {
        $outputChunks += $stdout.TrimEnd()
      }
    }
    if (Test-Path $stderrFile) {
      $stderr = Get-Content $stderrFile -Raw
      if (-not [string]::IsNullOrWhiteSpace($stderr)) {
        $outputChunks += $stderr.TrimEnd()
      }
    }

    return [ordered]@{
      ExitCode = $process.ExitCode
      Output = $outputChunks
    }
  }
  finally {
    Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue
  }
}

foreach ($check in $checks) {
  Write-Host "`n=== $($check.Title) ==="
  $result = Invoke-RosEnvCommand -Arguments @($check.Args)
  foreach ($chunk in $result.Output) {
    Write-Host $chunk
  }
  if ($result.ExitCode -ne 0) {
    throw "Проверка '$($check.Title)' завершилась с кодом $($result.ExitCode)."
  }
}

Write-Host "`n[ИНФО] Диагностика окружения завершена успешно."
