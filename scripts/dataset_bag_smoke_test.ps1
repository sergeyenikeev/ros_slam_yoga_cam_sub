[CmdletBinding()]
param(
  [int]$DurationSeconds = 4,
  [double]$PlaybackRate = 1.0,
  [int]$RequiredFrames = 10,
  [double]$MinFps = 1.0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$datasetName = 'smoke_dataset_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$datasetRoot = Join-Path $packageRoot 'artifacts\datasets'
$datasetPath = Join-Path $datasetRoot $datasetName
$bagPath = Join-Path $datasetPath 'bag'
$manifestPath = Join-Path $datasetPath 'dataset_manifest.json'
$catalogPath = Join-Path $datasetRoot 'dataset_catalog.json'
$reportPath = Join-Path $datasetPath 'reports\smoke_preflight_report.json'
$featureReportPath = Join-Path $datasetPath 'reports\smoke_feature_report.json'

Write-Host '[ИНФО] Запускаем smoke-тест записи и воспроизведения датасета.'

& (Join-Path $PSScriptRoot 'run_dataset_record.ps1') `
  -OutputRoot $datasetRoot `
  -DatasetName $datasetName `
  -DurationSeconds $DurationSeconds

if (-not (Test-Path (Join-Path $bagPath 'metadata.yaml'))) {
  throw "Smoke-тест не нашёл metadata.yaml в $bagPath"
}
if (-not (Test-Path $manifestPath)) {
  throw "Smoke-тест не нашёл dataset_manifest.json в $datasetPath"
}
if (-not (Test-Path $catalogPath)) {
  throw "Smoke-тест не нашёл dataset_catalog.json в $datasetRoot"
}

& (Join-Path $PSScriptRoot 'run_dataset_playback.ps1') `
  -BagPath $bagPath `
  -RunPreflight `
  -RequiredFrames $RequiredFrames `
  -MaxRuntimeSeconds 15 `
  -MinFps $MinFps `
  -Rate $PlaybackRate

& (Join-Path $PSScriptRoot 'run_dataset_report.ps1') `
  -BagPath $bagPath `
  -RunPreflight `
  -RequiredFrames $RequiredFrames `
  -MaxRuntimeSeconds 15 `
  -MinFps $MinFps `
  -Rate $PlaybackRate `
  -OutputFile $reportPath
if (-not (Test-Path $reportPath)) {
  throw "Smoke-тест не нашёл итоговый report-файл в $reportPath"
}

& (Join-Path $PSScriptRoot 'run_dataset_feature_report.ps1') `
  -BagPath $bagPath `
  -OutputFile $featureReportPath `
  -RequiredFrames 10 `
  -MaxRuntimeSeconds 15 `
  -SkipInitialFrames 10 `
  -MinAverageKeypoints 60 `
  -MinAverageGridCoverageRatio 0.20 `
  -MinAverageBlurScore 20.0 `
  -MinAverageBrightnessMean 15.0
if (-not (Test-Path $featureReportPath)) {
  throw "Smoke-тест не нашёл итоговый feature report-файл в $featureReportPath"
}

Write-Host '[ИНФО] Smoke-тест dataset bag завершён успешно.'
Write-Host "[ИНФО] Проверенный датасет: $datasetPath"
Write-Host "[ИНФО] Проверенный bag: $bagPath"
Write-Host "[ИНФО] Проверенный manifest: $manifestPath"
Write-Host "[ИНФО] Проверенный report: $reportPath"
Write-Host "[ИНФО] Проверенный feature report: $featureReportPath"


