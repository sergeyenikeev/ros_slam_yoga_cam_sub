[CmdletBinding()]
param(
  [string]$BagPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ([string]::IsNullOrWhiteSpace($BagPath)) {
  $latestDataset = Get-ChildItem -Path (Join-Path $packageRoot 'artifacts\datasets') -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $latestDataset) {
    throw 'Не найден ни один датасет для smoke-теста backend runner.'
  }
  $BagPath = Join-Path $latestDataset.FullName 'bag'
}

$experimentName = 'backend_runner_smoke_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$experimentRoot = Join-Path $packageRoot ('artifacts\slam_experiments\' + $experimentName)
$manifestPath = Join-Path $experimentRoot 'experiment_manifest.json'
$summaryPath = Join-Path $experimentRoot 'experiment_summary.md'
$backendResultPath = Join-Path $experimentRoot 'backend_artifacts\backend_result.json'
$trajectoryPath = Join-Path $experimentRoot 'backend_artifacts\mock_trajectory.csv'
$trajectoryReportPath = Join-Path $experimentRoot 'reports\trajectory_report.json'
$trajectorySummaryPath = Join-Path $experimentRoot 'reports\trajectory_report.md'
$mapPath = Join-Path $experimentRoot 'backend_artifacts\mock_map.json'
$runtimeLogPath = Join-Path $experimentRoot 'backend_artifacts\mock_runtime.log'
$catalogJsonPath = Join-Path $packageRoot 'artifacts\slam_experiments\slam_experiment_catalog.json'
$catalogMarkdownPath = Join-Path $packageRoot 'artifacts\slam_experiments\slam_experiment_catalog.md'
$catalogCsvPath = Join-Path $packageRoot 'artifacts\slam_experiments\slam_experiment_catalog.csv'

Write-Host '[ИНФО] Запускаем smoke-тест backend runner для monocular SLAM.'
& (Join-Path $PSScriptRoot 'run_slam_experiment.ps1') `
  -BagPath $BagPath `
  -ExperimentName $experimentName `
  -ConfigFile 'config/slam_experiment.template.json'

& (Join-Path $PSScriptRoot 'run_slam_backend.ps1') `
  -ExperimentPath $experimentRoot `
  -ConfigFile 'config/slam_backend.mock.template.json'

# Проверяем не только сырые артефакты mock-backend, но и нормализованный слой,
# который нужен для catalog/compare без повторного чтения backend-логов.
foreach ($path in @($manifestPath, $summaryPath, $backendResultPath, $trajectoryPath, $trajectoryReportPath, $trajectorySummaryPath, $mapPath, $runtimeLogPath, $catalogJsonPath, $catalogMarkdownPath, $catalogCsvPath)) {
  if (-not (Test-Path $path)) {
    throw "Smoke-тест backend runner не нашёл ожидаемый файл: $path"
  }
}

$manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.backend_result.runner.success) {
  throw 'Smoke-тест backend runner собрал manifest, но backend_result.runner.success=false.'
}
if (-not $manifest.backend_result.artifacts.trajectory_found) {
  throw 'Smoke-тест backend runner не подтвердил trajectory_found=true.'
}
if (-not $manifest.backend_result.artifacts.map_found) {
  throw 'Smoke-тест backend runner не подтвердил map_found=true.'
}
if (-not $manifest.backend_result.analysis.trajectory.success) {
  throw 'Smoke-тест backend runner не подтвердил успешный trajectory-анализ.'
}
if ($manifest.backend_result.analysis.trajectory.metrics.path_length_m -le 0.0) {
  throw 'Smoke-тест backend runner получил неположительную длину trajectory.'
}

Write-Host '[ИНФО] Smoke-тест backend runner завершён успешно.'
Write-Host "[ИНФО] experiment_manifest=$manifestPath"
