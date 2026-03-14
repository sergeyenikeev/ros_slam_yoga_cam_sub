[CmdletBinding()]
param(
  [string]$ImageTopic = '/camera/image_raw',
  [string]$CameraInfoTopic = '/camera/camera_info',
  [switch]$EchoMessages,
  [switch]$LaunchPublisher,
  [int]$PublisherStartupDelaySeconds = 3,
  [int]$PublisherMaxFrames = 300,
  [int]$EchoTimeoutSeconds = 30,
  [int]$DeviceIndex = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
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

try {
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
    $publisherProcess = Start-Process `
      -FilePath $envScript `
      -ArgumentList @('ros2', 'run', 'yoga_cam_sub', 'camera_publisher', '--ros-args', '-p', "device_index:=$DeviceIndex", '-p', "max_frames:=$PublisherMaxFrames") `
      -RedirectStandardOutput $publisherStdout `
      -RedirectStandardError $publisherStderr `
      -PassThru
    Start-Sleep -Seconds $PublisherStartupDelaySeconds
  }

  Write-Host '[ИНФО] Проверяем список ROS-топиков.'
  $topicList = @()
  $topicFound = $false
  for ($attempt = 1; $attempt -le 15; $attempt++) {
    $topicList = & $envScript ros2 topic list
    if ($LASTEXITCODE -ne 0) {
      throw 'Не удалось получить список ROS-топиков.'
    }

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
  foreach ($process in @($imageEchoProcess, $cameraInfoEchoProcess, $publisherProcess)) {
    if ($process -and -not $process.HasExited) {
      Stop-Process -Id $process.Id -Force
    }
  }
}
