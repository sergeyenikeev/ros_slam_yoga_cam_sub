[CmdletBinding()]
param(
  [string]$ConfigFile = 'config/slam_backend.orbslam3.local.json',
  [string]$ExperimentPath = '',
  [switch]$CheckRosEnv
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
. (Join-Path $PSScriptRoot 'process_utils.ps1')
. (Join-Path $PSScriptRoot 'slam_experiment_utils.ps1')

function Resolve-ConfigPath {
  param([string]$PathValue)

  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }

  return Join-Path $packageRoot $PathValue
}

function Resolve-CandidatePath {
  param(
    [string]$PathValue,
    [string[]]$BaseDirectories
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return ''
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }

  foreach ($baseDirectory in $BaseDirectories) {
    if ([string]::IsNullOrWhiteSpace($baseDirectory)) {
      continue
    }

    $candidate = Join-Path $baseDirectory $PathValue
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  return Join-Path $packageRoot $PathValue
}

function Test-HasTemplatePlaceholder {
  param([string]$Value)

  return -not [string]::IsNullOrWhiteSpace($Value) -and $Value -match '\{[^\}]+\}'
}

function Add-CheckResult {
  param(
    [System.Collections.Generic.List[object]]$Results,
    [string]$Name,
    [string]$Status,
    [string]$Details
  )

  $Results.Add([pscustomobject]@{
      Name = $Name
      Status = $Status
      Details = $Details
    })
}

$resolvedConfigPath = Resolve-ConfigPath -PathValue $ConfigFile
if (-not (Test-Path $resolvedConfigPath)) {
  throw "Config file was not found: $resolvedConfigPath"
}

$config = Get-Content -Path $resolvedConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$backendRunner = if ($config.PSObject.Properties['backend_runner']) { $config.backend_runner } else { $config }
$templateVariables = $backendRunner.template_variables
$results = [System.Collections.Generic.List[object]]::new()
$issues = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

if ($null -eq $templateVariables) {
  $issues.Add('backend_runner.template_variables section is missing.')
} else {
  $workdirValue = [string]$templateVariables.orbslam3_workdir
  $workdirIsDynamic = Test-HasTemplatePlaceholder -Value $workdirValue
  $workdirCandidate = if ($workdirIsDynamic) {
    $workdirValue
  } else {
    Resolve-CandidatePath -PathValue $workdirValue -BaseDirectories @($packageRoot)
  }

  $commandCandidate = Resolve-CandidatePath `
    -PathValue ([string]$templateVariables.orbslam3_command) `
    -BaseDirectories @($packageRoot, $workdirCandidate)
  $vocabularyCandidate = Resolve-CandidatePath `
    -PathValue ([string]$templateVariables.orbslam3_vocabulary_path) `
    -BaseDirectories @($workdirCandidate, $packageRoot)
  $settingsCandidate = Resolve-CandidatePath `
    -PathValue ([string]$templateVariables.orbslam3_settings_path) `
    -BaseDirectories @($workdirCandidate, $packageRoot)
  $trajectorySourceValue = [string]$templateVariables.orbslam3_trajectory_source
  $trajectorySourceCandidate = if ($workdirIsDynamic) {
    ('<dynamic under workdir>/' + $trajectorySourceValue)
  } elseif (-not [string]::IsNullOrWhiteSpace($workdirCandidate)) {
    Join-Path $workdirCandidate $trajectorySourceValue
  } else {
    Resolve-CandidatePath -PathValue $trajectorySourceValue -BaseDirectories @($workdirCandidate)
  }

  if (Test-Path $commandCandidate) {
    Add-CheckResult -Results $results -Name 'backend_command' -Status 'OK' -Details $commandCandidate
  } else {
    Add-CheckResult -Results $results -Name 'backend_command' -Status 'ERROR' -Details $commandCandidate
    $issues.Add("Backend command was not found: $commandCandidate")
  }

  if (Test-Path $vocabularyCandidate) {
    Add-CheckResult -Results $results -Name 'vocabulary_path' -Status 'OK' -Details $vocabularyCandidate
  } else {
    Add-CheckResult -Results $results -Name 'vocabulary_path' -Status 'ERROR' -Details $vocabularyCandidate
    $issues.Add("ORB vocabulary was not found: $vocabularyCandidate")
  }

  if (Test-Path $settingsCandidate) {
    Add-CheckResult -Results $results -Name 'settings_path' -Status 'OK' -Details $settingsCandidate
  } else {
    Add-CheckResult -Results $results -Name 'settings_path' -Status 'ERROR' -Details $settingsCandidate
    $issues.Add("ORB-SLAM3 settings file was not found: $settingsCandidate")
  }

  if ([string]::IsNullOrWhiteSpace($workdirCandidate)) {
    Add-CheckResult -Results $results -Name 'backend_workdir' -Status 'WARN' -Details '<empty>'
    $warnings.Add('Backend working directory is empty. The wrapper will fall back to the package root.')
  } elseif ($workdirIsDynamic) {
    Add-CheckResult -Results $results -Name 'backend_workdir' -Status 'INFO' -Details ($workdirCandidate + ' (dynamic placeholder)')
  } elseif (Test-Path $workdirCandidate) {
    Add-CheckResult -Results $results -Name 'backend_workdir' -Status 'OK' -Details $workdirCandidate
  } else {
    Add-CheckResult -Results $results -Name 'backend_workdir' -Status 'WARN' -Details $workdirCandidate
    $warnings.Add("Backend working directory does not exist yet and will be created on demand: $workdirCandidate")
  }

  if ([string]::IsNullOrWhiteSpace($trajectorySourceValue)) {
    Add-CheckResult -Results $results -Name 'trajectory_source' -Status 'ERROR' -Details '<empty>'
    $issues.Add('Trajectory source file name is empty.')
  } elseif ($workdirIsDynamic) {
    Add-CheckResult -Results $results -Name 'trajectory_source' -Status 'INFO' -Details $trajectorySourceCandidate
  } else {
    Add-CheckResult -Results $results -Name 'trajectory_source' -Status 'INFO' -Details $trajectorySourceCandidate
  }
}

if ([string]::IsNullOrWhiteSpace([string]$backendRunner.trajectory_path)) {
  $issues.Add('backend_runner.trajectory_path is empty.')
}
if ([string]::IsNullOrWhiteSpace([string]$backendRunner.runtime_log_path)) {
  $issues.Add('backend_runner.runtime_log_path is empty.')
}

if (-not [string]::IsNullOrWhiteSpace($ExperimentPath)) {
  try {
    $manifestPath = Resolve-SlamExperimentManifestPath -Path $ExperimentPath
    $manifest = Read-SlamExperimentManifest -Path $manifestPath
    Add-CheckResult -Results $results -Name 'experiment_manifest' -Status 'OK' -Details $manifestPath

    $bagPath = [string]$manifest.bag_root
    if ([string]::IsNullOrWhiteSpace($bagPath)) {
      $issues.Add('Experiment manifest does not contain bag_root.')
    } elseif (-not (Test-Path (Join-Path $bagPath 'metadata.yaml'))) {
      $issues.Add("Experiment bag is missing metadata.yaml: $bagPath")
      Add-CheckResult -Results $results -Name 'experiment_bag' -Status 'ERROR' -Details $bagPath
    } else {
      Add-CheckResult -Results $results -Name 'experiment_bag' -Status 'OK' -Details $bagPath
    }
  }
  catch {
    $issues.Add($_.Exception.Message)
    Add-CheckResult -Results $results -Name 'experiment_manifest' -Status 'ERROR' -Details $_.Exception.Message
  }
}

if ($CheckRosEnv) {
  try {
    $rosResult = Invoke-RosEnvCommand `
      -EnvScript $envScript `
      -Arguments @('ros2', 'pkg', 'list') `
      -AllowNonZeroExit `
      -FailureMessage 'ros2 pkg list failed.'

    if ($rosResult.ExitCode -ne 0) {
      $issues.Add("ros2 pkg list exited with code $($rosResult.ExitCode).")
      Add-CheckResult -Results $results -Name 'ros_env' -Status 'ERROR' -Details "exit_code=$($rosResult.ExitCode)"
    } elseif (-not ($rosResult.CombinedLines -contains 'yoga_cam_sub')) {
      $issues.Add('ROS environment does not list yoga_cam_sub.')
      Add-CheckResult -Results $results -Name 'ros_env' -Status 'ERROR' -Details 'yoga_cam_sub was not found in ros2 pkg list'
    } else {
      Add-CheckResult -Results $results -Name 'ros_env' -Status 'OK' -Details 'yoga_cam_sub is visible in ros2 pkg list'
    }
  }
  catch {
    $issues.Add($_.Exception.Message)
    Add-CheckResult -Results $results -Name 'ros_env' -Status 'ERROR' -Details $_.Exception.Message
  }
}

Write-Host '[INFO] ORB-SLAM3 setup check report'
Write-Host "[INFO] config_path=$resolvedConfigPath"
foreach ($result in $results) {
  Write-Host ("[{0}] {1}: {2}" -f $result.Status, $result.Name, $result.Details)
}

if ($warnings.Count -gt 0) {
  Write-Host '[INFO] Warnings:'
  foreach ($warningText in $warnings) {
    Write-Host ('- ' + $warningText)
  }
}

if ($issues.Count -gt 0) {
  Write-Host '[INFO] Blocking issues:'
  foreach ($issueText in $issues) {
    Write-Host ('- ' + $issueText)
  }
  exit 1
}

Write-Host '[INFO] Setup looks consistent.'
Write-Host '[INFO] Recommended next commands:'
Write-Host '.\scripts\orbslam3_backend_adapter_smoke_test.ps1'
if (-not [string]::IsNullOrWhiteSpace($ExperimentPath)) {
  Write-Host ('.\scripts\run_slam_backend.ps1 -ExperimentPath ' + $ExperimentPath + ' -ConfigFile ' + $resolvedConfigPath)
} else {
  Write-Host '.\scripts\run_slam_experiment.ps1 -BagPath C:\path\to\bag'
  Write-Host ('.\scripts\run_slam_backend.ps1 -ExperimentPath C:\path\to\experiment -ConfigFile ' + $resolvedConfigPath)
}
