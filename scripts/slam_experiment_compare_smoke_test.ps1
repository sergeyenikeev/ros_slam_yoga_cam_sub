[CmdletBinding()]
param(
  [string]$BagPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$experimentsRoot = Join-Path $packageRoot 'artifacts\slam_experiments'

function Get-ValidExperimentDirectories {
  param([string]$RootPath)

  if (-not (Test-Path $RootPath)) {
    return @()
  }

  return @(Get-ChildItem -Path $RootPath -Directory |
      Where-Object { Test-Path (Join-Path $_.FullName 'experiment_manifest.json') } |
      Sort-Object LastWriteTime -Descending)
}

function Get-TrajectoryComparableExperimentDirectories {
  param([string]$RootPath)

  $candidates = Get-ValidExperimentDirectories -RootPath $RootPath
  $comparable = [System.Collections.Generic.List[object]]::new()

  foreach ($candidate in $candidates) {
    $manifestPath = Join-Path $candidate.FullName 'experiment_manifest.json'
    $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $trajectoryAnalysisSuccess = $false
    if ($manifest.PSObject.Properties['backend_result'] -and
      $manifest.backend_result.PSObject.Properties['analysis'] -and
      $manifest.backend_result.analysis.PSObject.Properties['trajectory']) {
      $trajectoryAnalysisSuccess = [bool]$manifest.backend_result.analysis.trajectory.success
    }

    # Для compare smoke берём только те пакеты, где backend уже дошёл до
    # нормализованного trajectory-report. Иначе мы проверяли бы не trajectory compare,
    # а просто факт наличия каких-то experiment manifest.
    if ($trajectoryAnalysisSuccess) {
      $comparable.Add($candidate)
    }
  }

  # Возвращаем обычный массив, а не "массив как один объект", чтобы дальше
  # можно было безопасно делать Select-Object -First 2 и получать каталоги, а не контейнер.
  return @($comparable.ToArray())
}

if ([string]::IsNullOrWhiteSpace($BagPath)) {
  $latestDataset = Get-ChildItem -Path (Join-Path $packageRoot 'artifacts\datasets') -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $latestDataset) {
    throw 'Не найден ни один датасет для smoke-теста сравнения экспериментов.'
  }
  $BagPath = Join-Path $latestDataset.FullName 'bag'
}

$existingExperiments = Get-TrajectoryComparableExperimentDirectories -RootPath $experimentsRoot

# Для smoke-сравнения trajectory нам нужны два эксперимента, где backend runner
# уже сохранил валидный trajectory report по одному и тому же контракту CSV.
$neededExperiments = [Math]::Max(0, 2 - $existingExperiments.Count)
for ($index = 0; $index -lt $neededExperiments; $index++) {
  $experimentName = 'compare_smoke_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + "_$index"
  & (Join-Path $PSScriptRoot 'run_slam_experiment.ps1') `
    -BagPath $BagPath `
    -ExperimentName $experimentName `
    -ConfigFile 'config/slam_experiment.template.json'
  & (Join-Path $PSScriptRoot 'run_slam_backend.ps1') `
    -ExperimentPath (Join-Path $experimentsRoot $experimentName) `
    -ConfigFile 'config/slam_backend.mock.template.json'
  Start-Sleep -Seconds 1
}

$experimentsToCompare = @(Get-TrajectoryComparableExperimentDirectories -RootPath $experimentsRoot | Select-Object -First 2)
if ($experimentsToCompare.Count -lt 2) {
  throw 'Smoke-тест сравнения экспериментов не нашёл два доступных эксперимента с trajectory report.'
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
if (-not $comparison.backend) {
  throw 'Smoke-тест сравнения экспериментов не нашёл секцию backend в comparison.json.'
}
if (-not $comparison.trajectory.path_length_m) {
  throw 'Smoke-тест сравнения экспериментов не нашёл trajectory.path_length_m в comparison.json.'
}

Write-Host '[ИНФО] Smoke-тест сравнения экспериментов завершён успешно.'
Write-Host "[ИНФО] comparison_json=$comparisonJsonPath"
Write-Host "[ИНФО] comparison_summary=$comparisonSummaryPath"
