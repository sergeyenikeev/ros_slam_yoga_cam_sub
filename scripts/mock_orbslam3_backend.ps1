[CmdletBinding()]
param(
  [Parameter(Position = 0, Mandatory = $true)]
  [string]$VocabularyPath,
  [Parameter(Position = 1, Mandatory = $true)]
  [string]$SettingsPath,
  [int]$SleepSeconds = 2,
  [switch]$ShouldFail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedVocabularyPath = (Resolve-Path $VocabularyPath).Path
$resolvedSettingsPath = (Resolve-Path $SettingsPath).Path

Write-Host '[INFO] Mock ORB-SLAM3 monocular backend started.'
Write-Host "[INFO] vocabulary_path=$resolvedVocabularyPath"
Write-Host "[INFO] settings_path=$resolvedSettingsPath"
Write-Host "[INFO] working_directory=$((Get-Location).Path)"

Start-Sleep -Seconds $SleepSeconds

# Emit a typical ORB-SLAM3 artifact: a TUM trajectory in the process working
# directory. The wrapper will then copy it into the experiment packet.
$trajectoryLines = @(
  '# timestamp tx ty tz qx qy qz qw',
  '0.000000 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000 1.000000',
  '0.500000 0.030000 0.000000 0.000000 0.000000 0.000000 0.010000 0.999950',
  '1.000000 0.060000 0.005000 0.000000 0.000000 0.000000 0.020000 0.999800'
)
Set-Content -Path (Join-Path (Get-Location).Path 'CameraTrajectory.txt') -Value ($trajectoryLines -join "`r`n") -Encoding UTF8

$keyframeLines = @(
  '# timestamp tx ty tz qx qy qz qw',
  '0.000000 0.000000 0.000000 0.000000 0.000000 0.000000 0.000000 1.000000',
  '1.000000 0.060000 0.005000 0.000000 0.000000 0.000000 0.020000 0.999800'
)
Set-Content -Path (Join-Path (Get-Location).Path 'KeyFrameTrajectory.txt') -Value ($keyframeLines -join "`r`n") -Encoding UTF8

if ($ShouldFail) {
  Write-Host '[ERROR] Mock ORB-SLAM3 backend is failing on purpose for smoke coverage.'
  exit 7
}

Write-Host '[INFO] Mock ORB-SLAM3 monocular backend finished successfully.'

