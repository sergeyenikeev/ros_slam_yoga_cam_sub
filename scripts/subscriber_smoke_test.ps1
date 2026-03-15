[CmdletBinding()]
param(
  [int]$PublishTimes = 8,
  [double]$PublishRate = 8.0,
  [int]$SubscriberReadyTimeoutSeconds = 15,
  [int]$CompletionTimeoutSeconds = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
. (Join-Path $PSScriptRoot 'process_utils.ps1')
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\smoke_tests'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$stdoutFile = Join-Path $artifactRoot 'image_counter_stdout.log'
$stderrFile = Join-Path $artifactRoot 'image_counter_stderr.log'
Remove-Item $stdoutFile, $stderrFile -ErrorAction SilentlyContinue

function Stop-ProcessTree {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$ProcessName
  )

  if (-not $Process -or $Process.HasExited) {
    return
  }

  Write-Host "[ИНФО] Останавливаем дерево процесса $ProcessName (pid=$($Process.Id))."
  try {
    & taskkill /PID $Process.Id /T /F | Out-Null
  }
  catch {
    Write-Host "[ПРЕДУПРЕЖДЕНИЕ] Не удалось полностью остановить ${ProcessName}: $($_.Exception.Message)"
  }
}

function Stop-LingeringProjectProcesses {
  param([string]$Reason)

  $targets = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match 'image_counter|ros2|python' -and
    $_.CommandLine -match 'yoga_cam_sub|image_counter|/camera/image_raw|ros2 topic pub|smoke_tests'
  }

  if (-not $targets) {
    return
  }

  Write-Host "[ИНФО] Найдены зависшие процессы, очищаем окружение перед шагом: $Reason"
  foreach ($process in $targets | Sort-Object ProcessId -Unique) {
    try {
      Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
      Write-Host "[ИНФО] Остановлен зависший процесс pid=$($process.ProcessId) name=$($process.Name)."
    }
    catch {
      Write-Host "[ПРЕДУПРЕЖДЕНИЕ] Не удалось остановить процесс pid=$($process.ProcessId): $($_.Exception.Message)"
    }
  }
}

function ConvertTo-PowerShellLiteral {
  param([string]$Value)

  return "'" + ($Value -replace "'", "''") + "'"
}

function Start-RosProcess {
  param(
    [string[]]$RosArguments,
    [string]$StdoutPath,
    [string]$StderrPath
  )

  $commandParts = @("& $(ConvertTo-PowerShellLiteral -Value $envScript)")
  foreach ($argument in $RosArguments) {
    $commandParts += (ConvertTo-PowerShellLiteral -Value $argument)
  }
  # Держим UTF-8 и в smoke-сценариях, чтобы русские логи узлов можно было
  # безопасно парсить из файлов без ложных сбоев по кодировке.
  $commandText =
    "[Console]::InputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
    "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
    ($commandParts -join ' ') + '; exit $LASTEXITCODE'

  return Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandText) `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath `
    -PassThru
}

function Invoke-RosCommandViaPowerShell {
  param(
    [string[]]$RosArguments,
    [string]$FailureMessage
  )

  $commandParts = @("& $(ConvertTo-PowerShellLiteral -Value $envScript)")
  foreach ($argument in $RosArguments) {
    $commandParts += (ConvertTo-PowerShellLiteral -Value $argument)
  }
  $commandText = ($commandParts -join ' ') + '; exit $LASTEXITCODE'

  return Invoke-LoggedProcess `
    -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandText) `
    -PrintOutput `
    -FailureMessage $FailureMessage
}

function Get-CombinedLogText {
  param(
    [string]$StdoutPath,
    [string]$StderrPath
  )

  $combined = ''
  if (Test-Path $StdoutPath) {
    $combined += Get-Content $StdoutPath -Raw -Encoding UTF8
  }
  if (Test-Path $StderrPath) {
    $combined += "`n" + (Get-Content $StderrPath -Raw -Encoding UTF8)
  }
  return $combined
}

function Wait-ForLogPattern {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$ProcessName,
    [string]$StdoutPath,
    [string]$StderrPath,
    [string]$Pattern,
    [int]$TimeoutSeconds
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $combinedLogs = Get-CombinedLogText -StdoutPath $StdoutPath -StderrPath $StderrPath
    if ($combinedLogs.Contains($Pattern)) {
      return
    }
    if ($Process.HasExited) {
      throw "$ProcessName завершился до подтверждения готовности."
    }

    Start-Sleep -Milliseconds 250
  }

  throw "$ProcessName не подтвердил готовность в логах за $TimeoutSeconds секунд."
}

if ($PublishTimes -lt 1) {
  throw 'Параметр PublishTimes должен быть не меньше 1.'
}
if ($PublishRate -le 0.0) {
  throw 'Параметр PublishRate должен быть больше нуля.'
}

Stop-LingeringProjectProcesses -Reason 'smoke-тест image_counter'

Write-Host '[ИНФО] Запускаем image_counter для smoke-теста.'
$subscriberArguments = @(
  'ros2', 'run', 'yoga_cam_sub', 'image_counter',
  '--ros-args',
  '-p', 'image_topic:=/camera/image_raw',
  '-p', 'max_frames:=1'
)
$process = Start-RosProcess -RosArguments $subscriberArguments -StdoutPath $stdoutFile -StderrPath $stderrFile

try {
  # Ждём подтверждение запуска, чтобы не потерять единственные тестовые кадры на старте процесса.
  Wait-ForLogPattern `
    -Process $process `
    -ProcessName 'image_counter' `
    -StdoutPath $stdoutFile `
    -StderrPath $stderrFile `
    -Pattern 'max_frames=1' `
    -TimeoutSeconds $SubscriberReadyTimeoutSeconds

  Write-Host '[ИНФО] Публикуем серию тестовых сообщений в /camera/image_raw.'
  Invoke-RosCommandViaPowerShell `
    -RosArguments @(
      'ros2', 'topic', 'pub',
      '--times', "$PublishTimes",
      '--rate', "$PublishRate",
      '--keep-alive', '1.0',
      '--qos-profile', 'sensor_data',
      '--qos-history', 'keep_last',
      '--qos-depth', '5',
      '--wait-matching-subscriptions', '1',
      '--max-wait-time-secs', '10',
      '/camera/image_raw', 'sensor_msgs/msg/Image',
      "{header: {frame_id: 'test_camera'}, height: 1, width: 1, encoding: 'bgr8', is_bigendian: 0, step: 3, data: [1, 2, 3]}"
    ) `
    -FailureMessage 'Не удалось опубликовать тестовое сообщение.' | Out-Null

  if (-not $process.WaitForExit($CompletionTimeoutSeconds * 1000)) {
    throw 'image_counter не завершился после получения тестового сообщения.'
  }

  $combinedOutput = Get-CombinedLogText -StdoutPath $stdoutFile -StderrPath $stderrFile
  if ($combinedOutput -notmatch 'frame_id=test_camera width=1 height=1 encoding=bgr8 step=3') {
    throw "Smoke-тест не подтвердил обработку кадра. Лог: $stderrFile"
  }
  if ($combinedOutput -notmatch 'max_frames=1') {
    throw "Smoke-тест не подтвердил штатное завершение image_counter. Лог: $stderrFile"
  }
  $process.Refresh()
  $exitCodeText = if ($process.HasExited) { "$($process.ExitCode)" } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($exitCodeText) -and $exitCodeText -ne '0') {
    throw "image_counter завершился с кодом $exitCodeText."
  }

  Write-Host '[ИНФО] Smoke-тест image_counter завершён успешно.'
}
finally {
  Stop-ProcessTree -Process $process -ProcessName 'image_counter'
  Stop-LingeringProjectProcesses -Reason 'завершение smoke-теста image_counter'
}

