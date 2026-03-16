[CmdletBinding()]
param(
  [string]$BagPath = '',
  [string]$SeedExperiment = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'slam_experiment_utils.ps1')

function Get-ReusableSeedExperiment {
  param([string]$ExperimentsRoot)

  if (-not (Test-Path $ExperimentsRoot)) {
    return $null
  }

  $candidates = Get-ChildItem -Path $ExperimentsRoot -Directory |
    Sort-Object LastWriteTime -Descending

  foreach ($directory in $candidates) {
    $manifestPath = Join-Path $directory.FullName 'experiment_manifest.json'
    if (-not (Test-Path $manifestPath)) {
      continue
    }

    $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $preflightOk = [bool](Get-ObjectValue -Object $manifest -PathSegments @('preflight', 'success') -DefaultValue $false)
    $featureOk = [bool](Get-ObjectValue -Object $manifest -PathSegments @('feature_monitor', 'success') -DefaultValue $false)
    $backendStarted = $null -ne (Get-ObjectValue -Object $manifest -PathSegments @('backend_result', 'runner', 'started_at_utc') -DefaultValue $null)

    if ($preflightOk -and $featureOk -and -not $backendStarted) {
      return $directory.FullName
    }
  }

  return $null
}

function Initialize-ExperimentFromSeed {
  param(
    [string]$SeedRoot,
    [string]$TargetRoot,
    [string]$ExperimentName
  )

  Copy-Item -Path $SeedRoot -Destination $TargetRoot -Recurse

  $manifestPath = Join-Path $TargetRoot 'experiment_manifest.json'
  $summaryPath = Join-Path $TargetRoot 'experiment_summary.md'
  $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

  $manifest.generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
  $manifest.experiment_name = $ExperimentName
  $manifest.experiment_root = $TargetRoot
  $manifest.experiment.slam_backend = 'не_задан'
  $manifest.backend_result = [ordered]@{
    trajectory_path = ''
    map_path = ''
    runtime_log_path = ''
    result_notes = ''
  }

  $backendArtifactsRoot = Join-Path $TargetRoot 'backend_artifacts'
  if (Test-Path $backendArtifactsRoot) {
    Remove-Item -Path $backendArtifactsRoot -Recurse -Force
  }

  foreach ($path in @(
    (Join-Path $TargetRoot 'reports\trajectory_report.json'),
    (Join-Path $TargetRoot 'reports\trajectory_report.md')
  )) {
    Remove-Item -Path $path -ErrorAction SilentlyContinue
  }

  Save-SlamExperimentManifest -Manifest $manifest -ManifestPath $manifestPath
  Write-SlamExperimentSummary -Manifest $manifest -SummaryPath $summaryPath
}

if ([string]::IsNullOrWhiteSpace($BagPath)) {
  $latestDataset = Get-ChildItem -Path (Join-Path $packageRoot 'artifacts\datasets') -Directory |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if (-not $latestDataset) {
    throw 'No dataset found for ORB-SLAM3 adapter smoke test.'
  }
  $BagPath = Join-Path $latestDataset.FullName 'bag'
}

$experimentName = 'orbslam3_adapter_smoke_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
$experimentRoot = Join-Path $packageRoot ('artifacts\slam_experiments\' + $experimentName)
$manifestPath = Join-Path $experimentRoot 'experiment_manifest.json'
$runtimeLogPath = Join-Path $experimentRoot 'backend_artifacts\orbslam3\orbslam3_runtime.log'
$trajectoryPath = Join-Path $experimentRoot 'backend_artifacts\orbslam3\CameraTrajectory.txt'
$trajectoryReportPath = Join-Path $experimentRoot 'reports\trajectory_report.json'

Write-Host '[INFO] Running ORB-SLAM3 adapter smoke test.'

$seedExperimentRoot = if (-not [string]::IsNullOrWhiteSpace($SeedExperiment)) {
  (Resolve-Path $SeedExperiment).Path
} else {
  Get-ReusableSeedExperiment -ExperimentsRoot (Join-Path $packageRoot 'artifacts\slam_experiments')
}

if ($seedExperimentRoot) {
  Write-Host "[INFO] Reusing existing experiment packet as smoke seed: $seedExperimentRoot"
  Initialize-ExperimentFromSeed `
    -SeedRoot $seedExperimentRoot `
    -TargetRoot $experimentRoot `
    -ExperimentName $experimentName
} else {
  Write-Host '[INFO] No reusable experiment packet found, building a fresh one.'
  & (Join-Path $PSScriptRoot 'run_slam_experiment.ps1') `
    -BagPath $BagPath `
    -ExperimentName $experimentName `
    -ConfigFile 'config/slam_experiment.template.json'
}

& (Join-Path $PSScriptRoot 'run_slam_backend.ps1') `
  -ExperimentPath $experimentRoot `
  -ConfigFile 'config/slam_backend.orbslam3.mock.template.json'

foreach ($path in @($manifestPath, $runtimeLogPath, $trajectoryPath, $trajectoryReportPath)) {
  if (-not (Test-Path $path)) {
    throw "ORB-SLAM3 adapter smoke test did not find expected file: $path"
  }
}

$manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $manifest.backend_result.runner.success) {
  throw 'ORB-SLAM3 adapter smoke test got backend_result.runner.success=false.'
}
if (-not $manifest.backend_result.analysis.trajectory.success) {
  throw 'ORB-SLAM3 adapter smoke test did not confirm successful trajectory analysis.'
}
if ($manifest.backend_result.analysis.trajectory.format -ne 'tum_pose_v1') {
  throw "ORB-SLAM3 adapter smoke test expected trajectory format tum_pose_v1, got: $($manifest.backend_result.analysis.trajectory.format)"
}
if ($manifest.backend_result.analysis.trajectory.metrics.path_length_m -le 0.0) {
  throw 'ORB-SLAM3 adapter smoke test got non-positive trajectory path length.'
}

Write-Host '[INFO] ORB-SLAM3 adapter smoke test passed.'
Write-Host "[INFO] experiment_manifest=$manifestPath"
