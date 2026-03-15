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
function Invoke-EnvScript {
  param([string[]]$Arguments)

  $stdoutPath = Join-Path $env:TEMP ('yoga_cam_sub_tests_' + [System.Guid]::NewGuid().ToString('N') + '.stdout.log')
  $stderrPath = Join-Path $env:TEMP ('yoga_cam_sub_tests_' + [System.Guid]::NewGuid().ToString('N') + '.stderr.log')

  try {
    # И тут тоже отделяем stderr от PowerShell error stream, чтобы RTI/Fast DDS
    # warnings не ломали orchestration при успешном завершении colcon.
    $process = Start-Process `
      -FilePath $envScript `
      -ArgumentList $Arguments `
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

    return $process.ExitCode
  }
  finally {
    Remove-Item -Path $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
  }
}

$exitCode = Invoke-EnvScript -Arguments @('colcon', 'test', '--merge-install', '--packages-select', 'yoga_cam_sub', '--event-handlers', 'console_cohesion+')
if ($exitCode -ne 0) {
  throw "colcon test завершился с кодом $exitCode."
}

$exitCode = Invoke-EnvScript -Arguments @('colcon', 'test-result', '--verbose', '--test-result-base', 'build\yoga_cam_sub')
if ($exitCode -ne 0) {
  throw "colcon test-result завершился с кодом $exitCode."
}
