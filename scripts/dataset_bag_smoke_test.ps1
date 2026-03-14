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

Write-Host '[ИНФО] Запускаем smoke-тест записи и воспроизведения датасета.'

& (Join-Path $PSScriptRoot 'run_dataset_record.ps1') `
  -OutputRoot $datasetRoot `
  -DatasetName $datasetName `
  -DurationSeconds $DurationSeconds
if ($LASTEXITCODE -ne 0) {
  throw 'Запись bag-файла завершилась с ошибкой.'
}

if (-not (Test-Path (Join-Path $bagPath 'metadata.yaml'))) {
  throw "Smoke-тест не нашёл metadata.yaml в $bagPath"
}

& (Join-Path $PSScriptRoot 'run_dataset_playback.ps1') `
  -BagPath $bagPath `
  -RunPreflight `
  -RequiredFrames $RequiredFrames `
  -MaxRuntimeSeconds 15 `
  -MinFps $MinFps `
  -Rate $PlaybackRate
if ($LASTEXITCODE -ne 0) {
  throw 'Воспроизведение bag-файла завершилось с ошибкой.'
}

Write-Host '[ИНФО] Smoke-тест dataset bag завершён успешно.'
Write-Host "[ИНФО] Проверенный датасет: $datasetPath"
Write-Host "[ИНФО] Проверенный bag: $bagPath"
