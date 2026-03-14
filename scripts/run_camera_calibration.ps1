[CmdletBinding()]
param(
  [int]$BoardWidth = 8,
  [int]$BoardHeight = 6,
  [double]$SquareSize = 0.025,
  [string]$ImageTopic = '/camera/image_raw',
  [string]$CameraNamespace = '/camera',
  [string]$ParamsFile = '',
  [int]$DeviceIndex = 0,
  [int]$Width = 640,
  [int]$Height = 360,
  [double]$Fps = 30.0,
  [bool]$UseMsmf = $true,
  [int]$PublisherStartupDelaySeconds = 4,
  [switch]$SkipPublisher,
  [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\camera_calibration'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

if ([string]::IsNullOrWhiteSpace($ParamsFile)) {
  $ParamsFile = Join-Path $packageRoot 'config\camera_publisher.params.yaml'
}
if (-not (Test-Path $ParamsFile)) {
  throw "Файл параметров не найден: $ParamsFile"
}
if ($BoardWidth -le 0 -or $BoardHeight -le 0) {
  throw 'Размер шахматной доски должен быть положительным.'
}
if ($SquareSize -le 0.0) {
  throw 'Размер клетки шахматной доски должен быть больше нуля.'
}

function Normalize-CameraNamespace([string]$Namespace) {
  $trimmed = $Namespace.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) {
    throw 'Параметр CameraNamespace не должен быть пустым.'
  }
  if ($trimmed -eq '/') {
    return '/'
  }
  return '/' + $trimmed.Trim('/')
}

function Join-Topic([string]$Namespace, [string]$Suffix) {
  if ($Namespace -eq '/') {
    return "/$Suffix"
  }
  return "$Namespace/$Suffix"
}

function Test-CameraCalibrationTool {
  & $envScript cmd /c 'ros2 pkg list | findstr /x camera_calibration' | Out-Null
  return $LASTEXITCODE -eq 0
}

$normalizedCameraNamespace = Normalize-CameraNamespace $CameraNamespace
$cameraInfoTopic = Join-Topic $normalizedCameraNamespace 'camera_info'
$boardSpec = "${BoardWidth}x${BoardHeight}"
$calibrationCommand = @(
  'ros2', 'run', 'camera_calibration', 'cameracalibrator',
  '--size', $boardSpec,
  '--square', "$SquareSize",
  "image:=$ImageTopic",
  "camera:=$normalizedCameraNamespace"
)

Write-Host '[ИНФО] Подготавливаем запуск camera_calibration.'
Write-Host "[ИНФО] Параметры доски: $boardSpec, размер клетки: $SquareSize м."
Write-Host "[ИНФО] image_topic=$ImageTopic camera_namespace=$normalizedCameraNamespace camera_info_topic=$cameraInfoTopic"

if (-not (Test-CameraCalibrationTool)) {
  $message = @(
    'Пакет camera_calibration не найден в текущем ROS 2 underlay.',
    'Для Windows это означает, что GUI-калибратор не установлен в бинарном окружении.',
    'Подробности и обходной сценарий описаны в docs/calibration_and_slam.md.'
  ) -join ' '

  if ($CheckOnly) {
    Write-Warning $message
    Write-Host '[ИНФО] Команда для запуска после установки инструмента:'
    Write-Host ('scripts\run_in_ros_env.cmd ' + ($calibrationCommand -join ' '))
    exit 0
  }

  throw $message
}

if ($CheckOnly) {
  Write-Host '[ИНФО] Инструмент camera_calibration найден.'
  Write-Host '[ИНФО] Команда запуска:'
  Write-Host ('scripts\run_in_ros_env.cmd ' + ($calibrationCommand -join ' '))
  exit 0
}

$publisherProcess = $null
$publisherStdout = Join-Path $artifactRoot 'camera_publisher_stdout.log'
$publisherStderr = Join-Path $artifactRoot 'camera_publisher_stderr.log'

try {
  if (-not $SkipPublisher) {
    Remove-Item $publisherStdout, $publisherStderr -ErrorAction SilentlyContinue

    Write-Host '[ИНФО] Запускаем camera_publisher для подачи изображения в калибратор.'
    $publisherProcess = Start-Process `
      -FilePath $envScript `
      -ArgumentList @(
        'ros2', 'run', 'yoga_cam_sub', 'camera_publisher',
        '--ros-args',
        '--params-file', $ParamsFile,
        '-p', "device_index:=$DeviceIndex",
        '-p', "width:=$Width",
        '-p', "height:=$Height",
        '-p', "fps:=$Fps",
        '-p', "use_msmf:=$UseMsmf",
        '-p', "image_topic:=$ImageTopic",
        '-p', "camera_info_topic:=$cameraInfoTopic"
      ) `
      -RedirectStandardOutput $publisherStdout `
      -RedirectStandardError $publisherStderr `
      -PassThru

    Start-Sleep -Seconds $PublisherStartupDelaySeconds
  }

  Write-Host '[ИНФО] Запускаем camera_calibration.'
  & $envScript @calibrationCommand
  exit $LASTEXITCODE
}
finally {
  if ($publisherProcess -and -not $publisherProcess.HasExited) {
    Stop-Process -Id $publisherProcess.Id -Force
  }
}
