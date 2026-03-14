[CmdletBinding()]
param(
  [switch]$SkipCameraChecks,
  [switch]$SkipDatasetCheck,
  [switch]$SkipTfCheck,
  [switch]$SkipLaunchCheck,
  [int]$TopicPublisherMaxFrames = 120,
  [int]$TopicEchoTimeoutSeconds = 40,
  [int]$LaunchTimeoutSeconds = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host '[ИНФО] Запускаем полный автоматический прогон пакета yoga_cam_sub.'

$steps = @(
  @{ Name = 'Диагностика окружения'; Script = 'diagnose_environment.ps1'; Args = @() },
  @{ Name = 'Сборка workspace'; Script = 'build_workspace.ps1'; Args = @() },
  @{ Name = 'Пакет тестов'; Script = 'run_tests.ps1'; Args = @() },
  @{ Name = 'Smoke-тест YAML калибровки'; Script = 'calibration_file_smoke_test.ps1'; Args = @() },
  @{ Name = 'Smoke-тест image_counter'; Script = 'subscriber_smoke_test.ps1'; Args = @() }
)

foreach ($step in $steps) {
  Write-Host "`n=== $($step.Name) ==="
  $stepArgs = $step.Args
  & (Join-Path $PSScriptRoot $step.Script) @stepArgs
}

if (-not $SkipTfCheck) {
  Write-Host "`n=== Smoke-тест статического TF ==="
  & (Join-Path $PSScriptRoot 'tf_smoke_test.ps1')
}

if (-not $SkipCameraChecks) {
  Write-Host "`n=== Проверка топиков и реального publisher ==="
  & (Join-Path $PSScriptRoot 'check_topics.ps1') `
    -LaunchPublisher `
    -EchoMessages `
    -PublisherMaxFrames $TopicPublisherMaxFrames `
    -PublisherStartupDelaySeconds 4 `
    -EchoTimeoutSeconds $TopicEchoTimeoutSeconds

  Write-Host "`n=== SLAM preflight smoke-тест ==="
  & (Join-Path $PSScriptRoot 'slam_preflight_smoke_test.ps1')

  if (-not $SkipDatasetCheck) {
    Write-Host "`n=== Dataset bag smoke-тест ==="
    & (Join-Path $PSScriptRoot 'dataset_bag_smoke_test.ps1')
  }
}

if (-not $SkipLaunchCheck) {
  Write-Host "`n=== Launch smoke-тест ==="
  & (Join-Path $PSScriptRoot 'launch_smoke_test.ps1') -TimeoutSeconds $LaunchTimeoutSeconds
}

Write-Host "`n[ИНФО] Полный автоматический прогон завершён успешно."

