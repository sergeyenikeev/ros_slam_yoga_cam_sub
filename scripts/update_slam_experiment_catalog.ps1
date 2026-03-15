[CmdletBinding()]
param(
  [string]$ExperimentsRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'slam_experiment_utils.ps1')

if ([string]::IsNullOrWhiteSpace($ExperimentsRoot)) {
  $ExperimentsRoot = Join-Path $packageRoot 'artifacts\slam_experiments'
} elseif (-not [System.IO.Path]::IsPathRooted($ExperimentsRoot)) {
  $ExperimentsRoot = Join-Path $packageRoot $ExperimentsRoot
}

Write-Host '[ИНФО] Пересобираем каталог экспериментов monocular SLAM.'
$catalog = Update-SlamExperimentCatalogFile -ExperimentsRoot $ExperimentsRoot
$catalogPath = Get-SlamExperimentCatalogPath -ExperimentsRoot $ExperimentsRoot

Write-Host "[ИНФО] Каталог экспериментов обновлён: $catalogPath"
Write-Host "[ИНФО] experiment_count=$($catalog.experiment_count)"
