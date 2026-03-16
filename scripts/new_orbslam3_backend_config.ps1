[CmdletBinding()]
param(
  [string]$OutputFile = 'config/slam_backend.orbslam3.local.json',
  [string]$BackendCommand = '',
  [string]$WorkingDirectory = '',
  [string]$VocabularyPath = '',
  [string]$SettingsPath = '',
  [string]$TrajectorySourcePath = 'CameraTrajectory.txt',
  [double]$PlaybackRate = 1.0,
  [int]$StartupDelaySeconds = 5,
  [int]$PostPlaybackGraceSeconds = 10,
  [switch]$WithoutRosEnv,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$templatePath = Join-Path $packageRoot 'config\slam_backend.orbslam3.template.json'
$resolvedOutputPath = if ([System.IO.Path]::IsPathRooted($OutputFile)) {
  $OutputFile
} else {
  Join-Path $packageRoot $OutputFile
}

if (-not (Test-Path $templatePath)) {
  throw "Template file was not found: $templatePath"
}
if ((Test-Path $resolvedOutputPath) -and -not $Force) {
  throw "Output config already exists: $resolvedOutputPath. Use -Force to overwrite."
}
if ($PlaybackRate -le 0.0) {
  throw 'PlaybackRate must be greater than zero.'
}
if ($StartupDelaySeconds -lt 0) {
  throw 'StartupDelaySeconds cannot be negative.'
}
if ($PostPlaybackGraceSeconds -lt 0) {
  throw 'PostPlaybackGraceSeconds cannot be negative.'
}

$config = Get-Content -Path $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
$backendRunner = $config.backend_runner
$templateVariables = $backendRunner.template_variables

function Set-TemplateVariableValue {
  param(
    $VariablesObject,
    [string]$Name,
    [string]$Value
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return
  }

  $VariablesObject.$Name = $Value
}

Set-TemplateVariableValue -VariablesObject $templateVariables -Name 'orbslam3_command' -Value $BackendCommand
Set-TemplateVariableValue -VariablesObject $templateVariables -Name 'orbslam3_workdir' -Value $WorkingDirectory
Set-TemplateVariableValue -VariablesObject $templateVariables -Name 'orbslam3_vocabulary_path' -Value $VocabularyPath
Set-TemplateVariableValue -VariablesObject $templateVariables -Name 'orbslam3_settings_path' -Value $SettingsPath
Set-TemplateVariableValue -VariablesObject $templateVariables -Name 'orbslam3_trajectory_source' -Value $TrajectorySourcePath
$templateVariables.orbslam3_playback_rate = $PlaybackRate.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture)
$templateVariables.orbslam3_startup_delay_sec = [string]$StartupDelaySeconds
$templateVariables.orbslam3_post_playback_grace_sec = [string]$PostPlaybackGraceSeconds

if ($WithoutRosEnv) {
  $backendRunner.arguments = @($backendRunner.arguments | Where-Object { $_ -ne '-UseRosEnvForBackend' })
}

$backendRunner.result_notes = 'Local ORB-SLAM3 backend configuration generated from template.'

$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path $outputDirectory)) {
  New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}

Set-Content -Path $resolvedOutputPath -Value ($config | ConvertTo-Json -Depth 8) -Encoding UTF8

Write-Host '[INFO] ORB-SLAM3 local config created.'
Write-Host "[INFO] config_path=$resolvedOutputPath"
Write-Host '[INFO] Next steps:'
Write-Host ('.\scripts\check_orbslam3_setup.ps1 -ConfigFile ' + $resolvedOutputPath)
Write-Host ('.\scripts\run_slam_backend.ps1 -ExperimentPath C:\path\to\experiment -ConfigFile ' + $resolvedOutputPath)
