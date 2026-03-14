[CmdletBinding()]
param(
  [int]$TimeoutSeconds = 20,
  [string]$ParentFrame = 'camera_link',
  [string]$ChildFrame = 'camera_optical_frame'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$artifactRoot = Join-Path $packageRoot 'artifacts\tf_smoke_test'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

$publisherStdout = Join-Path $artifactRoot 'static_tf_stdout.log'
$publisherStderr = Join-Path $artifactRoot 'static_tf_stderr.log'
$echoStdout = Join-Path $artifactRoot 'tf_static_once.txt'
$echoStderr = Join-Path $artifactRoot 'tf_static_once.err.txt'
Remove-Item $publisherStdout, $publisherStderr, $echoStdout, $echoStderr -ErrorAction SilentlyContinue

Write-Host '[ИНФО] Запускаем smoke-тест статического TF.'
# Сначала проверяем, что наш launch-файл установлен и корректно парсится.
& $envScript ros2 launch yoga_cam_sub static_camera_tf.launch.py --show-args | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw 'Smoke-тест статического TF не смог провалидировать launch static_camera_tf.launch.py.'
}

# Затем публикуем сам transform напрямую, чтобы smoke-тест не зависел от долгоживущего ros2 launch процесса.
$publisherProcess = Start-Process `
  -FilePath $envScript `
  -ArgumentList @(
    'ros2', 'run', 'tf2_ros', 'static_transform_publisher',
    '0.0', '0.0', '0.0',
    '-1.57079632679', '0.0', '-1.57079632679',
    $ParentFrame, $ChildFrame
  ) `
  -RedirectStandardOutput $publisherStdout `
  -RedirectStandardError $publisherStderr `
  -PassThru

try {
  Start-Sleep -Seconds 3

  $echoProcess = Start-Process `
    -FilePath $envScript `
    -ArgumentList @('ros2', 'topic', 'echo', '--once', '/tf_static', 'tf2_msgs/msg/TFMessage') `
    -RedirectStandardOutput $echoStdout `
    -RedirectStandardError $echoStderr `
    -PassThru

  if (-not $echoProcess.WaitForExit($TimeoutSeconds * 1000)) {
    throw "Smoke-тест статического TF не получил сообщение /tf_static за $TimeoutSeconds секунд."
  }

  $echoContent = if (Test-Path $echoStdout) { Get-Content $echoStdout -Raw } else { '' }
  if ($echoContent -notmatch [regex]::Escape("frame_id: $ParentFrame")) {
    throw "Smoke-тест статического TF не нашёл parent frame '$ParentFrame'. Лог: $echoStdout"
  }
  if ($echoContent -notmatch [regex]::Escape("child_frame_id: $ChildFrame")) {
    throw "Smoke-тест статического TF не нашёл child frame '$ChildFrame'. Лог: $echoStdout"
  }

  Write-Host '[ИНФО] Smoke-тест статического TF завершён успешно.'
}
finally {
  foreach ($process in @($echoProcess, $publisherProcess)) {
    if ($process -and -not $process.HasExited) {
      Stop-Process -Id $process.Id -Force
    }
  }
}
