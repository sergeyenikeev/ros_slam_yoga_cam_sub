[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BagPath,
  [double]$Rate = 1.0,
  [switch]$RunImageCounter,
  [switch]$RunPreflight,
  [switch]$RunFeatureMonitor,
  [int]$StartupDelaySeconds = 2,
  [int]$CounterMaxFrames = 1,
  [int]$RequiredFrames = 10,
  [int]$MaxRuntimeSeconds = 15,
  [double]$MinFps = 1.0,
  [int]$FeatureRequiredFrames = 20,
  [int]$FeatureMaxRuntimeSeconds = 15,
  [int]$FeatureLogEveryNFrames = 10,
  [int]$FeatureMaxFeatures = 500,
  [int]$FeatureGridRows = 4,
  [int]$FeatureGridCols = 4,
  [int]$MinAverageKeypoints = 150,
  [double]$MinAverageGridCoverageRatio = 0.35,
  [double]$MinAverageBlurScore = 80.0,
  [double]$MinAverageBrightnessMean = 25.0,
  [string]$ImageTopic = '/camera/image_raw',
  [string]$CameraInfoTopic = '/camera/camera_info',
  [string]$ExpectedFrameId = 'camera_optical_frame'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\dataset_playback'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$resolvedBagPath = (Resolve-Path $BagPath).Path
if (-not (Test-Path (Join-Path $resolvedBagPath 'metadata.yaml'))) {
  throw "В каталоге bag не найден metadata.yaml: $resolvedBagPath"
}
if ($Rate -le 0.0) {
  throw 'Параметр Rate должен быть больше нуля.'
}
if (($RunImageCounter -or $RunPreflight -or $RunFeatureMonitor) -and $StartupDelaySeconds -lt 0) {
  throw 'Параметр StartupDelaySeconds не может быть отрицательным.'
}
if ((@(@($RunImageCounter, $RunPreflight, $RunFeatureMonitor) | Where-Object { $_ })).Count -gt 1) {
  throw 'Можно запускать только один режим подписчика: image_counter, preflight или feature_monitor.'
}

$playArguments = @(
  'ros2', 'bag', 'play',
  $resolvedBagPath.Replace('\', '/'),
  '-r', $Rate.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture)
)

$subscriberProcess = $null
$subscriberName = ''
$subscriberStdout = Join-Path $artifactRoot 'subscriber_stdout.log'
$subscriberStderr = Join-Path $artifactRoot 'subscriber_stderr.log'
Remove-Item $subscriberStdout, $subscriberStderr -ErrorAction SilentlyContinue

function Stop-ProcessTree {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$ProcessName
  )

  if (-not $Process -or $Process.HasExited) {
    return
  }

  # Playback также стартует через `run_in_ros_env.cmd`, поэтому при аварийной остановке
  # нужно завершить всё дерево процессов, а не только оболочку-обёртку.
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
    $_.Name -match 'camera_publisher|static_transform_publisher|image_counter|camera_slam_preflight|camera_feature_monitor|ros2|python' -and
    $_.CommandLine -match 'yoga_cam_sub|camera_slam_ready|camera_publisher|camera_slam_preflight|camera_feature_monitor|image_counter|ros2 bag record|ros2 bag play|artifacts/datasets|dataset_playback'
  }

  if (-not $targets) {
    return
  }

  Write-Host "[ИНФО] Найдены зависшие процессы проекта, очищаем окружение перед шагом: $Reason"
  foreach ($process in $targets | Sort-Object ProcessId -Unique) {
    try {
      Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
      Write-Host "[ИНФО] Остановлен зависший процесс pid=$($process.ProcessId) name=$($process.Name)."
    }
    catch {
      Write-Host "[ПРЕДУПРЕЖДЕНИЕ] Не удалось остановить зависший процесс pid=$($process.ProcessId): $($_.Exception.Message)"
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
  $commandText = ($commandParts -join ' ') + '; exit $LASTEXITCODE'

  return Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandText) `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath `
    -PassThru
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
    $combinedLogs = ''
    if (Test-Path $StdoutPath) {
      $combinedLogs += Get-Content $StdoutPath -Raw -Encoding UTF8
    }
    if (Test-Path $StderrPath) {
      $combinedLogs += "`n" + (Get-Content $StderrPath -Raw -Encoding UTF8)
    }

    if ($combinedLogs.Contains($Pattern)) {
      return
    }
    if ($Process.HasExited) {
      throw "$ProcessName завершился до подтверждения готовности."
    }

    Start-Sleep -Milliseconds 500
  }

  throw "$ProcessName не подтвердил готовность в логах за $TimeoutSeconds секунд."
}

Write-Host '[ИНФО] Подготавливаем воспроизведение датасета камеры.'
Write-Host "[ИНФО] bag_path=$resolvedBagPath"
Write-Host ('[ИНФО] Play: scripts\run_in_ros_env.cmd ' + ($playArguments -join ' '))
Stop-LingeringProjectProcesses -Reason 'воспроизведение rosbag-датасета'

try {
  if ($RunImageCounter) {
    $subscriberName = 'image_counter'
    $subscriberArguments = @(
      'ros2', 'run', 'yoga_cam_sub', 'image_counter',
      '--ros-args',
      '-p', "image_topic:=$ImageTopic",
      '-p', "max_frames:=$CounterMaxFrames"
    )

    # Поднимаем subscriber заранее, чтобы не потерять первые сообщения bagplay.
    $subscriberProcess = Start-RosProcess `
      -RosArguments $subscriberArguments `
      -StdoutPath $subscriberStdout `
      -StderrPath $subscriberStderr
  } elseif ($RunPreflight) {
    $subscriberName = 'camera_slam_preflight'
    $subscriberArguments = @(
      'ros2', 'run', 'yoga_cam_sub', 'camera_slam_preflight',
      '--ros-args',
      '-p', "image_topic:=$ImageTopic",
      '-p', "camera_info_topic:=$CameraInfoTopic",
      '-p', "expected_frame_id:=$ExpectedFrameId",
      '-p', "required_frames:=$RequiredFrames",
      '-p', "max_runtime_seconds:=$MaxRuntimeSeconds",
      '-p', "min_fps:=$($MinFps.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture))"
    )

    $subscriberProcess = Start-RosProcess `
      -RosArguments $subscriberArguments `
      -StdoutPath $subscriberStdout `
      -StderrPath $subscriberStderr
  } elseif ($RunFeatureMonitor) {
    $subscriberName = 'camera_feature_monitor'
    $subscriberArguments = @(
      'ros2', 'run', 'yoga_cam_sub', 'camera_feature_monitor',
      '--ros-args',
      '-p', "image_topic:=$ImageTopic",
      '-p', "required_frames:=$FeatureRequiredFrames",
      '-p', "max_runtime_seconds:=$FeatureMaxRuntimeSeconds",
      '-p', "log_every_n_frames:=$FeatureLogEveryNFrames",
      '-p', "max_features:=$FeatureMaxFeatures",
      '-p', "grid_rows:=$FeatureGridRows",
      '-p', "grid_cols:=$FeatureGridCols",
      '-p', "min_average_keypoints:=$MinAverageKeypoints",
      '-p', "min_average_grid_coverage_ratio:=$($MinAverageGridCoverageRatio.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture))",
      '-p', "min_average_blur_score:=$($MinAverageBlurScore.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture))",
      '-p', "min_average_brightness_mean:=$($MinAverageBrightnessMean.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture))"
    )

    $subscriberProcess = Start-RosProcess `
      -RosArguments $subscriberArguments `
      -StdoutPath $subscriberStdout `
      -StderrPath $subscriberStderr
  }

  if ($subscriberProcess) {
    $readyPattern = if ($RunPreflight) {
      'Узел camera_slam_preflight запущен.'
    } elseif ($RunImageCounter) {
      'Узел image_counter запущен.'
    } else {
      # Для feature-монитора на Windows логи старта могут буферизоваться дольше,
      # чем нам нужно ждать перед `ros2 bag play`, поэтому опираемся на StartupDelaySeconds.
      ''
    }
    if ($readyPattern) {
      Wait-ForLogPattern `
        -Process $subscriberProcess `
        -ProcessName $subscriberName `
        -StdoutPath $subscriberStdout `
        -StderrPath $subscriberStderr `
        -Pattern $readyPattern `
        -TimeoutSeconds 15
    }

    if ($StartupDelaySeconds -gt 0) {
      Start-Sleep -Seconds $StartupDelaySeconds
    }
  }

  & $envScript @playArguments
  if ($LASTEXITCODE -ne 0) {
    throw "ros2 bag play завершился с кодом $LASTEXITCODE."
  }

  if ($subscriberProcess) {
    $waitSeconds = if ($RunPreflight) {
      $MaxRuntimeSeconds + 5
    } elseif ($RunFeatureMonitor) {
      $FeatureMaxRuntimeSeconds + 5
    } else {
      10
    }
    if (-not $subscriberProcess.WaitForExit($waitSeconds * 1000)) {
      Stop-Process -Id $subscriberProcess.Id -Force
      throw "$subscriberName не завершился после окончания bagplay за $waitSeconds секунд."
    }

    $subscriberStdoutText = if (Test-Path $subscriberStdout) {
      Get-Content $subscriberStdout -Raw -Encoding UTF8
    } else {
      ''
    }
    if ($subscriberStdoutText) {
      $subscriberStdoutText | Write-Host
    }
    $stderrContent = if (Test-Path $subscriberStderr) {
      Get-Content $subscriberStderr -Raw -Encoding UTF8
    } else {
      ''
    }
    if ($stderrContent) {
      $stderrContent | Write-Host
    }

    $subscriberProcess.Refresh()
    $subscriberExitCodeText = "$($subscriberProcess.ExitCode)"
    $subscriberLogText = $subscriberStdoutText + "`n" + $stderrContent
    $successPattern = if ($RunPreflight) {
      'SLAM preflight завершён успешно'
    } elseif ($RunFeatureMonitor) {
      'Feature monitor завершён успешно'
    } elseif ($RunImageCounter) {
      'Достигнут лимит max_frames='
    } else {
      ''
    }

    if ($successPattern -and -not $subscriberLogText.Contains($successPattern)) {
      throw "$subscriberName не подтвердил успешное завершение в логах."
    }
    if (-not [string]::IsNullOrWhiteSpace($subscriberExitCodeText) -and $subscriberExitCodeText -ne '0') {
      throw "$subscriberName завершился с кодом $subscriberExitCodeText."
    }
  }

  Write-Host '[ИНФО] Воспроизведение датасета завершено успешно.'
}
finally {
  Stop-ProcessTree -Process $subscriberProcess -ProcessName $subscriberName
}
