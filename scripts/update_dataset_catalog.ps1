[CmdletBinding()]
param(
  [string]$DatasetsRoot = '',
  [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if ([string]::IsNullOrWhiteSpace($DatasetsRoot)) {
  $DatasetsRoot = Join-Path $packageRoot 'artifacts\datasets'
}
if (-not [System.IO.Path]::IsPathRooted($DatasetsRoot)) {
  $DatasetsRoot = Join-Path $packageRoot $DatasetsRoot
}

. (Join-Path $PSScriptRoot 'dataset_catalog_utils.ps1')

$catalog = Update-DatasetCatalogFile -DatasetsRoot $DatasetsRoot -RepositoryRoot $packageRoot
$catalogPath = Get-DatasetCatalogPath -DatasetsRoot $DatasetsRoot

if (-not $Quiet) {
  Write-Host '[ИНФО] Каталог датасетов обновлён.'
  Write-Host "[ИНФО] Файл каталога: $catalogPath"
  Write-Host "[ИНФО] Количество датасетов: $($catalog.dataset_count)"

  if ($catalog.dataset_count -gt 0) {
    # Показываем короткую сводку по последним датасетам, чтобы быстро выбрать bag для следующего SLAM-прогона.
    $catalog.datasets |
      Select-Object dataset_name, storage_id, duration_seconds, image_messages, width, height, fps, use_msmf_selected |
      Format-Table -AutoSize
  }
}

