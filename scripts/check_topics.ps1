[CmdletBinding()]
param(
  [string]$ImageTopic = '/camera/image_raw',
  [string]$CameraInfoTopic = '/camera/camera_info',
  [switch]$EchoMessages,
  [switch]$LaunchPublisher,
  [int]$PublisherStartupDelaySeconds = 3,
  [int]$PublisherMaxFrames = 300,
  [int]$EchoTimeoutSeconds = 30,
  [int]$DeviceIndex = 0,
  [int]$PublisherWidth = 640,
  [int]$PublisherHeight = 360,
  [double]$PublisherFps = 30.0,
  [string]$PublisherFrameId = 'camera_optical_frame',
  [bool]$PublisherUseMsmf = $true,
  [string]$CalibrationFile = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
. (Join-Path $PSScriptRoot 'process_utils.ps1')
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\topic_checks'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$publisherProcess = $null
$imageEchoProcess = $null
$cameraInfoEchoProcess = $null
$publisherStdout = Join-Path $artifactRoot 'camera_publisher_stdout.log'
$publisherStderr = Join-Path $artifactRoot 'camera_publisher_stderr.log'
$imageFile = Join-Path $artifactRoot 'image_raw_once.txt'
$imageErrFile = Join-Path $artifactRoot 'image_raw_once.err.txt'
$cameraInfoFile = Join-Path $artifactRoot 'camera_info_once.txt'
$cameraInfoErrFile = Join-Path $artifactRoot 'camera_info_once.err.txt'
$fpsString = $PublisherFps.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture)
$useMsmfString = $PublisherUseMsmf.ToString().ToLowerInvariant()

function Stop-ProcessTree {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$ProcessName
  )

  if (-not $Process -or $Process.HasExited) {
    return
  }

  # `run_in_ros_env.cmd` поднимает вложенное дерево `cmd.exe -> ros2 -> node`, поэтому
  # завершаем именно дерево процессов, чтобы не оставлять фоновые ROS-узлы после ошибки.
  Write-Host "[ИНФО] Останавливаем дерево процесса $ProcessName (pid=$($Process.Id))."
  & taskkill /PID $Process.Id /T /F | Out-Null
}

function Stop-LingeringProjectProcesses {
  param([string]$Reason)

  $targets = Get-CimInstance Win32_Process | Where-Object {
    $_.Name -match 'camera_publisher|static_transform_publisher|image_counter|camera_slam_preflight|ros2|python' -and
    $_.CommandLine -match 'yoga_cam_sub|camera_publisher|camera_slam_preflight|image_counter|ros2 topic echo|artifacts/topic_checks'
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

try {
  Stop-LingeringProjectProcesses -Reason 'проверка топиков'

  if ($EchoMessages) {
    Remove-Item $imageFile, $imageErrFile, $cameraInfoFile, $cameraInfoErrFile -ErrorAction SilentlyContinue

    Write-Host '[ИНФО] Подготавливаем процессы ros2 topic echo --once.'
    $imageEchoProcess = Start-Process `
      -FilePath $envScript `
      -ArgumentList @('ros2', 'topic', 'echo', '--once', $ImageTopic, 'sensor_msgs/msg/Image', '--qos-reliability', 'best_effort') `
      -RedirectStandardOutput $imageFile `
      -RedirectStandardError $imageErrFile `
      -PassThru
    $cameraInfoEchoProcess = Start-Process `
      -FilePath $envScript `
      -ArgumentList @('ros2', 'topic', 'echo', '--once', $CameraInfoTopic, 'sensor_msgs/msg/CameraInfo', '--qos-reliability', 'best_effort') `
      -RedirectStandardOutput $cameraInfoFile `
      -RedirectStandardError $cameraInfoErrFile `
      -PassThru
    Start-Sleep -Seconds 2
  }

  if ($LaunchPublisher) {
    Remove-Item $publisherStdout, $publisherStderr -ErrorAction SilentlyContinue
    Write-Host '[ИНФО] Запускаем camera_publisher для проверки топиков.'
    $publisherArguments = @(
      'ros2', 'run', 'yoga_cam_sub', 'camera_publisher',
      '--ros-args',
      '-p', "device_index:=$DeviceIndex",
      '-p', "width:=$PublisherWidth",
      '-p', "height:=$PublisherHeight",
      '-p', "fps:=$fpsString",
      '-p', "frame_id:=$PublisherFrameId",
      '-p', "use_msmf:=$useMsmfString",
      '-p', "max_frames:=$PublisherMaxFrames"
    )
    if (-not [string]::IsNullOrWhiteSpace($CalibrationFile)) {
      $publisherArguments += @('-p', "calibration_file:=$CalibrationFile")
    }

    $publisherProcess = Start-Process `
      -FilePath $envScript `
      -ArgumentList $publisherArguments `
      -RedirectStandardOutput $publisherStdout `
      -RedirectStandardError $publisherStderr `
      -PassThru
    Start-Sleep -Seconds $PublisherStartupDelaySeconds
  }

  Write-Host '[ИНФО] Проверяем список ROS-топиков.'
  $topicList = @()
  $topicFound = $false
  for ($attempt = 1; $attempt -le 15; $attempt++) {
    $topicListResult = Invoke-RosEnvCommand `
      -EnvScript $envScript `
      -Arguments @('ros2', 'topic', 'list') `
      -FailureMessage 'Не удалось получить список ROS-топиков.'
    $topicList = @($topicListResult.StdOutLines)

    if (($topicList -contains $ImageTopic) -and ($topicList -contains $CameraInfoTopic)) {
      $topicFound = $true
      break
    }

    Start-Sleep -Seconds 1
  }

  if (-not $topicFound) {
    throw "Топики '$ImageTopic' и '$CameraInfoTopic' не появились в ROS graph за отведённое время."
  }

  Write-Host "[ИНФО] Найдены топики '$ImageTopic' и '$CameraInfoTopic'."

  if ($EchoMessages) {
    if (-not $imageEchoProcess.WaitForExit($EchoTimeoutSeconds * 1000)) {
      throw "ros2 topic echo для '$ImageTopic' не завершился за $EchoTimeoutSeconds секунд."
    }
    if (-not $cameraInfoEchoProcess.WaitForExit($EchoTimeoutSeconds * 1000)) {
      throw "ros2 topic echo для '$CameraInfoTopic' не завершился за $EchoTimeoutSeconds секунд."
    }

    $imageContent = if (Test-Path $imageFile) { Get-Content $imageFile -Raw } else { '' }
    $cameraInfoContent = if (Test-Path $cameraInfoFile) { Get-Content $cameraInfoFile -Raw } else { '' }

    if ($imageContent -notmatch 'encoding: bgr8') {
      throw "Сообщение из '$ImageTopic' не содержит ожидаемое поле encoding: bgr8."
    }
    if ($cameraInfoContent -notmatch 'distortion_model:') {
      throw "Сообщение из '$CameraInfoTopic' не содержит ожидаемое поле distortion_model."
    }

    Write-Host "[ИНФО] Сообщения сохранены в $artifactRoot."
  }
}
finally {
  Stop-ProcessTree -Process $imageEchoProcess -ProcessName 'ros2 topic echo image'
  Stop-ProcessTree -Process $cameraInfoEchoProcess -ProcessName 'ros2 topic echo camera_info'
  Stop-ProcessTree -Process $publisherProcess -ProcessName 'camera_publisher'
}
