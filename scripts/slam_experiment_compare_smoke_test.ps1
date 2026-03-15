[CmdletBinding()]
param(
  [string]$BagPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$experimentsRoot = Join-Path $packageRoot 'artifacts\slam_experiments'

if ([string]::IsNullOrWhiteSpace($BagPath)) {
  $latestDataset = Get-ChildItem -Path (Join-Path $packageRoot 'artifacts\datasets') -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $latestDataset) {
    throw 'Не найден ни один датасет для smoke-теста сравнения экспериментов.'
  }
  $BagPath = Join-Path $latestDataset.FullName 'bag'
}

$existingExperiments = @()
if (Test-Path $experimentsRoot) {
  $existingExperiments = @(Get-ChildItem -Path $experimentsRoot -Directory | Sort-Object LastWriteTime -Descending)
}

# Для надёжного smoke-теста нам нужно минимум два experiment manifest.
# Если их ещё нет, создаём недостающие пакеты поверх одного и того же bag.
$neededExperiments = [Math]::Max(0, 2 - $existingExperiments.Count)
for ($index = 0; $index -lt $neededExperiments; $index++) {
  $experimentName = 'compare_smoke_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + "_$index"
  & (Join-Path $PSScriptRoot 'run_slam_experiment.ps1') `
    -BagPath $BagPath `
    -ExperimentName $experimentName `
    -ConfigFile 'config/slam_experiment.template.json'
  Start-Sleep -Seconds 1
}

$experimentsToCompare = @(Get-ChildItem -Path $experimentsRoot -Directory |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 2)
if ($experimentsToCompare.Count -lt 2) {
  throw 'Smoke-тест сравнения экспериментов не нашёл два доступных эксперимента.'
}

$comparisonName = 'compare_smoke_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$comparisonRoot = Join-Path $packageRoot ('artifacts\slam_experiment_comparisons\' + $comparisonName)
$comparisonJsonPath = Join-Path $comparisonRoot 'comparison.json'
$comparisonSummaryPath = Join-Path $comparisonRoot 'comparison_summary.md'

Write-Host '[ИНФО] Запускаем smoke-тест сравнения экспериментов monocular SLAM.'
& (Join-Path $PSScriptRoot 'compare_slam_experiments.ps1') `
  -BaselineExperiment $experimentsToCompare[1].FullName `
  -CandidateExperiment $experimentsToCompare[0].FullName `
  -ComparisonName $comparisonName

foreach ($path in @($comparisonJsonPath, $comparisonSummaryPath)) {
  if (-not (Test-Path $path)) {
    throw "Smoke-тест сравнения экспериментов не нашёл ожидаемый файл: $path"
  }
}

$comparison = Get-Content -Path $comparisonJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $comparison.metrics.average_fps) {
  throw 'Smoke-тест сравнения экспериментов не нашёл average_fps в comparison.json.'
}

Write-Host '[ИНФО] Smoke-тест сравнения экспериментов завершён успешно.'
Write-Host "[ИНФО] comparison_json=$comparisonJsonPath"
Write-Host "[ИНФО] comparison_summary=$comparisonSummaryPath"
