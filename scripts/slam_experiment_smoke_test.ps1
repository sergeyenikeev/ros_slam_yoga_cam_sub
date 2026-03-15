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
    throw 'Не найден ни один датасет для smoke-теста эксперимента.'
  }
  $BagPath = Join-Path $latestDataset.FullName 'bag'
}

$experimentName = 'smoke_experiment_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$experimentRoot = Join-Path $packageRoot ('artifacts\slam_experiments\' + $experimentName)
$manifestPath = Join-Path $experimentRoot 'experiment_manifest.json'
$summaryPath = Join-Path $experimentRoot 'experiment_summary.md'
$preflightReportPath = Join-Path $experimentRoot 'reports\preflight_report.json'
$featureReportPath = Join-Path $experimentRoot 'reports\feature_report.json'
$catalogJsonPath = Join-Path $packageRoot 'artifacts\slam_experiments\slam_experiment_catalog.json'
$catalogMarkdownPath = Join-Path $packageRoot 'artifacts\slam_experiments\slam_experiment_catalog.md'
$catalogCsvPath = Join-Path $packageRoot 'artifacts\slam_experiments\slam_experiment_catalog.csv'

Write-Host '[ИНФО] Запускаем smoke-тест пакета эксперимента monocular SLAM.'
& (Join-Path $PSScriptRoot 'run_slam_experiment.ps1') `
  -BagPath $BagPath `
  -ExperimentName $experimentName `
  -ConfigFile 'config/slam_experiment.template.json'

foreach ($path in @($manifestPath, $summaryPath, $preflightReportPath, $featureReportPath, $catalogJsonPath, $catalogMarkdownPath, $catalogCsvPath)) {
  if (-not (Test-Path $path)) {
    throw "Smoke-тест не нашёл ожидаемый файл: $path"
  }
}

$experimentManifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $experimentManifest.experiment.ready_for_slam) {
  throw 'Smoke-тест пакета эксперимента собрал manifest, но ready_for_slam=false.'
}

Write-Host '[ИНФО] Smoke-тест пакета эксперимента завершён успешно.'
Write-Host "[ИНФО] Проверенный experiment manifest: $manifestPath"
Write-Host "[ИНФО] Проверенный preflight report: $preflightReportPath"
Write-Host "[ИНФО] Проверенный feature report: $featureReportPath"
