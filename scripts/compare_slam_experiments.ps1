[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BaselineExperiment,
  [Parameter(Mandatory = $true)]
  [string]$CandidateExperiment,
  [string]$OutputRoot = '',
  [string]$ComparisonName = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'slam_experiment_utils.ps1')

function Get-MetricLine {
  param([object]$Metric)

  $deltaText = if ($null -eq $Metric.delta) {
    'n/a'
  } else {
    $Metric.delta
  }

  return "- $($Metric.name): baseline=$($Metric.baseline); candidate=$($Metric.candidate); delta=$deltaText"
}

$baselineManifestPath = Resolve-SlamExperimentManifestPath -Path $BaselineExperiment
$candidateManifestPath = Resolve-SlamExperimentManifestPath -Path $CandidateExperiment
$baselineManifest = Read-SlamExperimentManifest -Path $baselineManifestPath
$candidateManifest = Read-SlamExperimentManifest -Path $candidateManifestPath

if ([string]::IsNullOrWhiteSpace($ComparisonName)) {
  $ComparisonName = 'compare_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
}
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $packageRoot 'artifacts\slam_experiment_comparisons'
} elseif (-not [System.IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot = Join-Path $packageRoot $OutputRoot
}

$comparisonRoot = Join-Path $OutputRoot $ComparisonName
if (Test-Path $comparisonRoot) {
  throw "Каталог сравнения уже существует: $comparisonRoot"
}
New-Item -ItemType Directory -Force -Path $comparisonRoot | Out-Null

# Сравнение строится только по manifest/report-данным, чтобы его можно было
# выполнять offline без физической камеры и без подключённого SLAM backend.
$comparison = Compare-SlamExperimentManifests `
  -BaselineManifest $baselineManifest `
  -CandidateManifest $candidateManifest `
  -BaselineManifestPath $baselineManifestPath `
  -CandidateManifestPath $candidateManifestPath

$comparisonJsonPath = Join-Path $comparisonRoot 'comparison.json'
$comparisonSummaryPath = Join-Path $comparisonRoot 'comparison_summary.md'
Set-Content -Path $comparisonJsonPath -Value ($comparison | ConvertTo-Json -Depth 10) -Encoding UTF8

$summaryLines = @(
  '# Сравнение экспериментов monocular SLAM',
  '',
  "- baseline: $($comparison.baseline.experiment_name)",
  "- candidate: $($comparison.candidate.experiment_name)",
  "- same_dataset: $($comparison.compatibility.same_dataset)",
  "- baseline_ready_for_slam: $($comparison.readiness.baseline_ready_for_slam)",
  "- candidate_ready_for_slam: $($comparison.readiness.candidate_ready_for_slam)",
  ''
)
$summaryLines += '## Ключевые метрики'
$summaryLines += ''
foreach ($metricName in @('average_fps', 'average_keypoints', 'average_coverage', 'average_blur', 'average_brightness')) {
  $summaryLines += Get-MetricLine -Metric $comparison.metrics.$metricName
}
$summaryLines += @(
  '',
  '## Ручная оценка backend',
  '',
  "- baseline_tracking_lost: $(Get-ExperimentTrackingLostLabel -Value $comparison.manual_assessment.baseline_tracking_lost)",
  "- candidate_tracking_lost: $(Get-ExperimentTrackingLostLabel -Value $comparison.manual_assessment.candidate_tracking_lost)",
  "- baseline_map_quality: $($comparison.manual_assessment.baseline_map_quality)",
  "- candidate_map_quality: $($comparison.manual_assessment.candidate_map_quality)",
  '',
  '## Выполнение backend',
  '',
  "- baseline_backend_success: $($comparison.backend.baseline_success)",
  "- candidate_backend_success: $($comparison.backend.candidate_success)",
  "- baseline_trajectory_found: $($comparison.backend.baseline_trajectory_found)",
  "- candidate_trajectory_found: $($comparison.backend.candidate_trajectory_found)",
  "- baseline_map_found: $($comparison.backend.baseline_map_found)",
  "- candidate_map_found: $($comparison.backend.candidate_map_found)",
  '',
  '## Выводы',
  ''
)
foreach ($note in @($comparison.notes)) {
  $summaryLines += "- $note"
}
Set-Content -Path $comparisonSummaryPath -Value ($summaryLines -join "`r`n") -Encoding UTF8

Write-Host '[ИНФО] Сравнение экспериментов monocular SLAM успешно подготовлено.'
Write-Host "[ИНФО] comparison_json=$comparisonJsonPath"
Write-Host "[ИНФО] comparison_summary=$comparisonSummaryPath"
