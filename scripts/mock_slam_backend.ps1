[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BagPath,
  [Parameter(Mandatory = $true)]
  [string]$ExperimentName,
  [Parameter(Mandatory = $true)]
  [string]$TrajectoryPath,
  [Parameter(Mandatory = $true)]
  [string]$MapPath,
  [Parameter(Mandatory = $true)]
  [string]$RuntimeLogPath,
  [int]$SleepSeconds = 1,
  [switch]$ShouldFail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $BagPath 'metadata.yaml'))) {
  throw "Mock-backend не нашёл metadata.yaml в bag: $BagPath"
}

foreach ($targetPath in @($TrajectoryPath, $MapPath, $RuntimeLogPath)) {
  $targetDirectory = Split-Path -Parent $targetPath
  if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path $targetDirectory)) {
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
  }
}

Write-Host '[ИНФО] Запущен mock monocular SLAM backend.'
Write-Host "[ИНФО] experiment_name=$ExperimentName"
Write-Host "[ИНФО] bag_path=$BagPath"

# Этот скрипт нужен только для smoke-проверки backend runner:
# он создаёт минимальный набор артефактов, похожих на результат SLAM backend.
Start-Sleep -Seconds $SleepSeconds

$trajectoryLines = @(
  'timestamp_sec,x,y,z,qx,qy,qz,qw',
  '0.000,0.000,0.000,0.000,0.000,0.000,0.000,1.000',
  '0.500,0.030,0.000,0.000,0.000,0.000,0.010,1.000',
  '1.000,0.060,0.005,0.000,0.000,0.000,0.020,1.000'
)
Set-Content -Path $TrajectoryPath -Value ($trajectoryLines -join "`r`n") -Encoding UTF8

$mapSummary = [ordered]@{
  schema_version = 1
  backend_name = 'mock_monocular_backend'
  experiment_name = $ExperimentName
  keyframes = 3
  map_points = 128
  tracking_lost = $false
}
Set-Content -Path $MapPath -Value ($mapSummary | ConvertTo-Json -Depth 4) -Encoding UTF8

$runtimeLines = @(
  'Mock backend runtime log',
  "experiment_name=$ExperimentName",
  "bag_path=$BagPath",
  'status=success'
)
Set-Content -Path $RuntimeLogPath -Value ($runtimeLines -join "`r`n") -Encoding UTF8

if ($ShouldFail) {
  Write-Host '[ОШИБКА] Mock-backend завершает работу с ошибкой по запросу smoke-сценария.'
  exit 7
}

Write-Host '[ИНФО] Mock monocular SLAM backend завершён успешно.'
