[CmdletBinding()]
param(
  [string]$OutputRoot = '',
  [string]$DatasetName = '',
  [int]$DurationSeconds = 5,
  [int]$StartupDelaySeconds = 4,
  [string]$CalibrationFile = '',
  [string]$StorageId = 'sqlite3',
  [int]$DeviceIndex = 0,
  [int]$Width = 640,
  [int]$Height = 360,
  [double]$Fps = 30.0,
  [string]$FrameId = 'camera_optical_frame',
  [bool]$UseMsmf = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$datasetUtils = Join-Path $PSScriptRoot 'dataset_catalog_utils.ps1'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. $datasetUtils

function Stop-ProcessTree {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$ProcessName
  )

  if (-not $Process -or $Process.HasExited) {
    return
  }

  # `run_in_ros_env.cmd` порождает дерево `cmd.exe -> ros2 -> launch/node`, поэтому
  # для корректной уборки останавливаем весь процессный хвост, а не только wrapper.
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
    $_.Name -match 'camera_publisher|static_transform_publisher|image_counter|camera_slam_preflight|ros2|python' -and
    $_.CommandLine -match 'yoga_cam_sub|camera_slam_ready|camera_publisher|camera_slam_preflight|image_counter|ros2 bag record|ros2 bag play|artifacts/datasets|dataset_playback'
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

function Invoke-RecordingAttempt {
  param(
    [bool]$CandidateUseMsmf,
    [int]$AttemptIndex
  )

  $attemptLabel = if ($CandidateUseMsmf) {
    "attempt_${AttemptIndex}_msmf"
  } else {
    "attempt_${AttemptIndex}_cap_any"
  }
  $fpsString = $Fps.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture)
  $useMsmfString = $CandidateUseMsmf.ToString().ToLowerInvariant()
  $cameraStdout = Join-Path $logRoot "camera_slam_ready_${attemptLabel}_stdout.log"
  $cameraStderr = Join-Path $logRoot "camera_slam_ready_${attemptLabel}_stderr.log"
  $bagStdout = Join-Path $logRoot "rosbag_record_${attemptLabel}_stdout.log"
  $bagStderr = Join-Path $logRoot "rosbag_record_${attemptLabel}_stderr.log"
  $bagInfoFile = Join-Path $logRoot "rosbag_info_${attemptLabel}.txt"
  $finalCameraStdout = Join-Path $logRoot 'camera_slam_ready_stdout.log'
  $finalCameraStderr = Join-Path $logRoot 'camera_slam_ready_stderr.log'
  $finalBagStdout = Join-Path $logRoot 'rosbag_record_stdout.log'
  $finalBagStderr = Join-Path $logRoot 'rosbag_record_stderr.log'
  $finalBagInfoFile = Join-Path $logRoot 'rosbag_info.txt'
  $bagFilePattern = switch ($StorageId) {
    'mcap' { '*.mcap' }
    'sqlite3' { '*.db3' }
    default { 'bag_*.*' }
  }

  Remove-Item -Path @(
    $cameraStdout,
    $cameraStderr,
    $bagStdout,
    $bagStderr,
    $bagInfoFile,
    $finalCameraStdout,
    $finalCameraStderr,
    $finalBagStdout,
    $finalBagStderr,
    $finalBagInfoFile
  ) -Force -ErrorAction SilentlyContinue
  Remove-Item $bagRoot -Recurse -Force -ErrorAction SilentlyContinue

  $launchArguments = @(
    'ros2', 'launch', 'yoga_cam_sub', 'camera_slam_ready.launch.py',
    "device_index:=$DeviceIndex",
    "width:=$Width",
    "height:=$Height",
    "fps:=$fpsString",
    "frame_id:=$FrameId",
    "use_msmf:=$useMsmfString",
    'max_frames:=0'
  )
  if (-not [string]::IsNullOrWhiteSpace($CalibrationFile)) {
    $launchArguments += "calibration_file:=$CalibrationFile"
  }

  $bagPathForRos = $bagRoot.Replace('\', '/')
  $recordArguments = @(
    'ros2', 'bag', 'record',
    '-o', $bagPathForRos,
    '-s', $StorageId,
    '--topics', '/camera/image_raw', '/camera/camera_info', '/tf_static'
  )

  Write-Host "[ИНФО] Попытка записи ${AttemptIndex}: use_msmf=$useMsmfString storage_id=$StorageId."
  Write-Host ('[ИНФО] Record: scripts\run_in_ros_env.cmd ' + ($recordArguments -join ' '))
  Write-Host ('[ИНФО] Launch: scripts\run_in_ros_env.cmd ' + ($launchArguments -join ' '))

  $cameraProcess = $null
  $bagProcess = $null
  try {
    # Сначала поднимаем rosbag recorder, чтобы он успел открыть output и подписаться
    # до появления статического TF и первых кадров камеры.
    $bagProcess = Start-Process `
      -FilePath $envScript `
      -ArgumentList $recordArguments `
      -RedirectStandardOutput $bagStdout `
      -RedirectStandardError $bagStderr `
      -PassThru

    Start-Sleep -Seconds 2
    if ($bagProcess.HasExited) {
      throw "ros2 bag record завершился слишком рано с кодом $($bagProcess.ExitCode)."
    }

    $cameraProcess = Start-Process `
      -FilePath $envScript `
      -ArgumentList $launchArguments `
      -RedirectStandardOutput $cameraStdout `
      -RedirectStandardError $cameraStderr `
      -PassThru

    if ($StartupDelaySeconds -gt 0) {
      Start-Sleep -Seconds $StartupDelaySeconds
    }

    $bagReady = $false
    $cameraReady = $false
    $readyDeadline = (Get-Date).AddSeconds([Math]::Max(18, $StartupDelaySeconds + 12))
    while ((Get-Date) -lt $readyDeadline) {
      if ($cameraProcess.HasExited) {
        throw "camera_slam_ready.launch.py завершился раньше времени с кодом $($cameraProcess.ExitCode)."
      }
      if ($bagProcess.HasExited) {
        throw "ros2 bag record завершился раньше времени с кодом $($bagProcess.ExitCode)."
      }

      $bagFiles = @(Get-ChildItem -Path $bagRoot -Filter $bagFilePattern -ErrorAction SilentlyContinue)
      if ($bagFiles.Count -gt 0) {
        $bagReady = $true
      }

      $cameraLogs = ''
      if (Test-Path $cameraStdout) {
        $cameraLogs += Get-Content $cameraStdout -Raw -Encoding UTF8
      }
      if (Test-Path $cameraStderr) {
        $cameraLogs += "`n" + (Get-Content $cameraStderr -Raw -Encoding UTF8)
      }
      if ($cameraLogs.Contains('Опубликован кадр #')) {
        $cameraReady = $true
      }

      # Ждём не только создания файла bag, но и фактической публикации хотя бы одного кадра,
      # чтобы датасет точно содержал изображения, а не только /tf_static и CameraInfo.
      if ($bagReady -and $cameraReady) {
        break
      }

      Start-Sleep -Seconds 1
    }

    if (-not $bagReady) {
      throw "rosbag не создал ожидаемый файл $bagFilePattern после старта камеры. Проверьте логи publisher и recorder."
    }
    if (-not $cameraReady) {
      $lastCameraLines = @()
      if (Test-Path $cameraStdout) {
        $lastCameraLines += (Get-Content $cameraStdout -Encoding UTF8 | Select-Object -Last 8)
      }
      if (Test-Path $cameraStderr) {
        $lastCameraLines += (Get-Content $cameraStderr -Encoding UTF8 | Select-Object -Last 8)
      }
      if ($lastCameraLines) {
        Write-Host '[ПРЕДУПРЕЖДЕНИЕ] Последние строки логов camera_slam_ready перед ошибкой:'
        $lastCameraLines | ForEach-Object { Write-Host $_ }
      }
      throw 'camera_slam_ready не подтвердил публикацию кадров за отведённое время.'
    }

    Start-Sleep -Seconds $DurationSeconds
  }
  finally {
    Stop-ProcessTree -Process $bagProcess -ProcessName 'ros2 bag record'
    Stop-ProcessTree -Process $cameraProcess -ProcessName 'camera_slam_ready.launch.py'
  }

  Start-Sleep -Seconds 2

  if (-not (Test-Path $bagRoot)) {
    throw "Каталог bag не был создан: $bagRoot"
  }

  Write-Host '[ИНФО] Восстанавливаем metadata.yaml через ros2 bag reindex.'
  $reindexOutput = & $envScript ros2 bag reindex $bagPathForRos
  if ($LASTEXITCODE -ne 0) {
    throw "ros2 bag reindex завершился с кодом $LASTEXITCODE."
  }
  if ($reindexOutput) {
    $reindexOutput | ForEach-Object { Write-Host $_ }
  }

  if (-not (Test-Path (Join-Path $bagRoot 'metadata.yaml'))) {
    throw "После записи не найден metadata.yaml в $bagRoot"
  }

  Write-Host '[ИНФО] Получаем информацию о записанном bag-файле.'
  $bagInfoLines = & $envScript ros2 bag info $bagPathForRos
  if ($LASTEXITCODE -ne 0) {
    throw "ros2 bag info завершился с кодом $LASTEXITCODE."
  }
  $bagInfoLines | Tee-Object -FilePath $bagInfoFile | ForEach-Object { Write-Host $_ }

  $bagInfoText = if (Test-Path $bagInfoFile) { Get-Content $bagInfoFile -Raw -Encoding UTF8 } else { '' }
  foreach ($requiredTopic in @('/camera/image_raw', '/camera/camera_info', '/tf_static')) {
    $topicPattern = 'Topic:\s+' + [regex]::Escape($requiredTopic) + '\s+\|.*Count:\s+(\d+)'
    $topicMatch = [regex]::Match($bagInfoText, $topicPattern)
    if (-not $topicMatch.Success) {
      throw "ros2 bag info не нашёл обязательный топик $requiredTopic."
    }
    if ([int]$topicMatch.Groups[1].Value -le 0) {
      throw "ros2 bag info нашёл топик $requiredTopic, но в нём нет сообщений."
    }
  }

  Copy-Item $cameraStdout $finalCameraStdout -Force
  Copy-Item $cameraStderr $finalCameraStderr -Force
  Copy-Item $bagStdout $finalBagStdout -Force
  Copy-Item $bagStderr $finalBagStderr -Force
  Copy-Item $bagInfoFile $finalBagInfoFile -Force

  $recordingParameters = [ordered]@{
    duration_seconds = $DurationSeconds
    startup_delay_seconds = $StartupDelaySeconds
    device_index = $DeviceIndex
    width = $Width
    height = $Height
    fps = $Fps
    frame_id = $FrameId
    calibration_file = $CalibrationFile
    storage_id = $StorageId
    use_msmf_requested = $UseMsmf
    use_msmf_selected = $CandidateUseMsmf
  }
  $manifestPath = Get-DatasetManifestPath -DatasetRoot $datasetRoot
  $manifest = New-DatasetManifest `
    -DatasetName $DatasetName `
    -DatasetRoot $datasetRoot `
    -BagRoot $bagRoot `
    -LogRoot $logRoot `
    -RecordingParameters $recordingParameters `
    -BagInfoText $bagInfoText `
    -GitSnapshot (Get-GitSnapshot -RepositoryRoot $packageRoot) `
    -ManifestSource 'record'
  Save-DatasetManifest -Manifest $manifest -ManifestPath $manifestPath

  return $useMsmfString
}

if ($DurationSeconds -le 0) {
  throw 'Параметр DurationSeconds должен быть положительным.'
}
if ($StartupDelaySeconds -lt 0) {
  throw 'Параметр StartupDelaySeconds не может быть отрицательным.'
}
if ($Width -le 0 -or $Height -le 0) {
  throw 'Параметры Width и Height должны быть положительными.'
}
if ($Fps -le 0.0) {
  throw 'Параметр Fps должен быть больше нуля.'
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $packageRoot 'artifacts\datasets'
}
if ([string]::IsNullOrWhiteSpace($DatasetName)) {
  $DatasetName = 'camera_dataset_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
}
if (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot = Join-Path $packageRoot $OutputRoot
}

$datasetRoot = Join-Path $OutputRoot $DatasetName
$bagRoot = Join-Path $datasetRoot 'bag'
$logRoot = Join-Path $datasetRoot 'logs'
if (Test-Path $datasetRoot) {
  throw "Каталог датасета уже существует: $datasetRoot"
}
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($CalibrationFile)) {
  $localCalibration = Join-Path $packageRoot 'config\camera_calibration.local.yaml'
  if (Test-Path $localCalibration) {
    $CalibrationFile = $localCalibration.Replace('\', '/')
  }
}

$candidateModes = if ($UseMsmf) { @($true, $false) } else { @($false, $true) }
Write-Host '[ИНФО] Подготавливаем запись датасета камеры.'
Write-Host "[ИНФО] dataset_root=$datasetRoot"
Write-Host "[ИНФО] bag_root=$bagRoot"
Stop-LingeringProjectProcesses -Reason 'запись rosbag-датасета'
$selectedBackendString = $null
$attemptErrors = @()
$attemptIndex = 0
foreach ($candidateMode in $candidateModes | Select-Object -Unique) {
  $attemptIndex++
  try {
    $selectedBackendString = Invoke-RecordingAttempt -CandidateUseMsmf $candidateMode -AttemptIndex $attemptIndex
    break
  }
  catch {
    $attemptErrors += "Попытка $attemptIndex (use_msmf=$candidateMode): $($_.Exception.Message)"
    Write-Host "[ПРЕДУПРЕЖДЕНИЕ] Попытка записи $attemptIndex завершилась неуспешно: $($_.Exception.Message)"
    Start-Sleep -Seconds 2
  }
}

if (-not $selectedBackendString) {
  throw ('Не удалось записать датасет ни одним режимом backend OpenCV. ' + ($attemptErrors -join ' | '))
}

$catalog = Update-DatasetCatalogFile -DatasetsRoot $OutputRoot -RepositoryRoot $packageRoot
$manifestPath = Get-DatasetManifestPath -DatasetRoot $datasetRoot
$catalogPath = Get-DatasetCatalogPath -DatasetsRoot $OutputRoot

Write-Host '[ИНФО] Запись датасета завершена успешно.'
Write-Host "[ИНФО] Успешный backend-приоритет use_msmf=$selectedBackendString"
Write-Host "[ИНФО] Каталог датасета: $datasetRoot"
Write-Host "[ИНФО] Каталог bag-файла: $bagRoot"
Write-Host "[ИНФО] Манифест датасета: $manifestPath"
Write-Host "[ИНФО] Каталог датасетов обновлён: $catalogPath (dataset_count=$($catalog.dataset_count))"


