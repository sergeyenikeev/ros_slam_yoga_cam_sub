[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BagPath,
  [Parameter(Mandatory = $true)]
  [string]$ExperimentName,
  [Parameter(Mandatory = $true)]
  [string]$TrajectoryPath,
  [string]$MapPath = '',
  [Parameter(Mandatory = $true)]
  [string]$RuntimeLogPath,
  [Parameter(Mandatory = $true)]
  [string]$BackendCommand,
  [Parameter(Mandatory = $true)]
  [string]$VocabularyPath,
  [Parameter(Mandatory = $true)]
  [string]$SettingsPath,
  [string[]]$BackendArguments = @(),
  [string]$BackendWorkingDirectory = '',
  [string]$TrajectorySourcePath = 'CameraTrajectory.txt',
  [string]$MapSourcePath = '',
  [double]$PlaybackRate = 1.0,
  [int]$StartupDelaySeconds = 5,
  [int]$PostPlaybackGraceSeconds = 10,
  [switch]$UseRosEnvForBackend,
  [switch]$CheckOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$envScript = Join-Path $PSScriptRoot 'run_in_ros_env.cmd'
. (Join-Path $PSScriptRoot 'process_utils.ps1')

function ConvertTo-PowerShellLiteral {
  param([string]$Value)

  return "'" + ($Value -replace "'", "''") + "'"
}

function Resolve-SupportPath {
  param(
    [string]$PathValue,
    [string]$BaseDirectory,
    [switch]$AllowMissing
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return ''
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    if ($AllowMissing -or (Test-Path $PathValue)) {
      return $PathValue
    }
    throw "Path not found: $PathValue"
  }

  $baseCandidate = ''
  if (-not [string]::IsNullOrWhiteSpace($BaseDirectory)) {
    $baseCandidate = Join-Path $BaseDirectory $PathValue
    if ($AllowMissing -or (Test-Path $baseCandidate)) {
      return $baseCandidate
    }
  }

  $packageCandidate = Join-Path $packageRoot $PathValue
  if ($AllowMissing -or (Test-Path $packageCandidate)) {
    return $packageCandidate
  }

  throw "Path not found: $PathValue"
}

function Write-Utf8TextFile {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  $directory = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path $directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
  }

  Set-Content -Path $Path -Value ($Lines -join "`r`n") -Encoding UTF8
}

function Read-OptionalUtf8File {
  param([string]$Path)

  $content = Get-Content -Path $Path -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
  if ($null -eq $content) {
    return ''
  }

  return [string]$content
}

function Stop-ProcessTree {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$ProcessName
  )

  if (-not $Process -or $Process.HasExited) {
    return
  }

  Write-Host "[INFO] Stopping process tree $ProcessName (pid=$($Process.Id))."
  try {
    & taskkill /PID $Process.Id /T /F | Out-Null
  }
  catch {
    Write-Host "[WARN] Failed to stop ${ProcessName} completely: $($_.Exception.Message)"
  }
}

function Start-ManagedProcess {
  param(
    [string]$CommandPath,
    [string[]]$Arguments,
    [string]$WorkingDirectory,
    [string]$StdoutPath,
    [string]$StderrPath,
    [switch]$UseRosEnv
  )

  if ($UseRosEnv) {
    $commandParts = @("& $(ConvertTo-PowerShellLiteral -Value $envScript)", (ConvertTo-PowerShellLiteral -Value $CommandPath))
    foreach ($argument in $Arguments) {
      $commandParts += (ConvertTo-PowerShellLiteral -Value ([string]$argument))
    }

    $commandText =
      "[Console]::InputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
      "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
      ($commandParts -join ' ') + '; exit $LASTEXITCODE'

    return Start-Process `
      -FilePath 'powershell.exe' `
      -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandText) `
      -WorkingDirectory $WorkingDirectory `
      -RedirectStandardOutput $StdoutPath `
      -RedirectStandardError $StderrPath `
      -PassThru
  }

  if ([System.IO.Path]::GetExtension($CommandPath).ToLowerInvariant() -eq '.ps1') {
    $commandText = '& ' + (ConvertTo-PowerShellLiteral -Value $CommandPath)
    foreach ($argument in $Arguments) {
      $commandText += ' ' + (ConvertTo-PowerShellLiteral -Value ([string]$argument))
    }
    $commandText = "[Console]::InputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
      "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
      $commandText + '; exit $LASTEXITCODE'

    return Start-Process `
      -FilePath 'powershell.exe' `
      -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandText) `
      -WorkingDirectory $WorkingDirectory `
      -RedirectStandardOutput $StdoutPath `
      -RedirectStandardError $StderrPath `
      -PassThru
  }

  return Start-Process `
    -FilePath $CommandPath `
    -ArgumentList $Arguments `
    -WorkingDirectory $WorkingDirectory `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath `
    -PassThru
}

function Copy-ArtifactIfPresent {
  param(
    [string]$SourcePath,
    [string]$TargetPath,
    [string]$ArtifactName
  )

  if ([string]::IsNullOrWhiteSpace($TargetPath)) {
    return "<${ArtifactName}_not_requested>"
  }
  if (Test-Path $TargetPath) {
    return "<${ArtifactName}_already_present>"
  }
  if ([string]::IsNullOrWhiteSpace($SourcePath)) {
    return "<${ArtifactName}_source_not_configured>"
  }
  if (-not (Test-Path $SourcePath)) {
    return "<${ArtifactName}_source_missing:$SourcePath>"
  }

  $targetDirectory = Split-Path -Parent $TargetPath
  if (-not [string]::IsNullOrWhiteSpace($targetDirectory) -and -not (Test-Path $targetDirectory)) {
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
  }

  Copy-Item -Path $SourcePath -Destination $TargetPath -Force
  return "<${ArtifactName}_copied_from:$SourcePath>"
}

$resolvedBagPath = (Resolve-Path $BagPath).Path
if (-not (Test-Path (Join-Path $resolvedBagPath 'metadata.yaml'))) {
  throw "metadata.yaml was not found in bag directory: $resolvedBagPath"
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

$resolvedBackendCommand = Resolve-SupportPath -PathValue $BackendCommand -BaseDirectory $packageRoot -AllowMissing
$resolvedBackendWorkingDirectory = if ([string]::IsNullOrWhiteSpace($BackendWorkingDirectory)) {
  if ([System.IO.Path]::IsPathRooted($resolvedBackendCommand) -or (Test-Path $resolvedBackendCommand)) {
    Split-Path -Parent $resolvedBackendCommand
  } else {
    $packageRoot
  }
} else {
  Resolve-SupportPath -PathValue $BackendWorkingDirectory -BaseDirectory $packageRoot -AllowMissing
}
$resolvedVocabularyPath = Resolve-SupportPath -PathValue $VocabularyPath -BaseDirectory $resolvedBackendWorkingDirectory
$resolvedSettingsPath = Resolve-SupportPath -PathValue $SettingsPath -BaseDirectory $resolvedBackendWorkingDirectory
$resolvedTrajectoryPath = Resolve-SupportPath -PathValue $TrajectoryPath -BaseDirectory $packageRoot -AllowMissing
$resolvedMapPath = if ([string]::IsNullOrWhiteSpace($MapPath)) {
  ''
} else {
  Resolve-SupportPath -PathValue $MapPath -BaseDirectory $packageRoot -AllowMissing
}
$resolvedRuntimeLogPath = Resolve-SupportPath -PathValue $RuntimeLogPath -BaseDirectory $packageRoot -AllowMissing
$resolvedTrajectorySourcePath = if ([string]::IsNullOrWhiteSpace($TrajectorySourcePath)) {
  ''
} else {
  Resolve-SupportPath -PathValue $TrajectorySourcePath -BaseDirectory $resolvedBackendWorkingDirectory -AllowMissing
}
$resolvedMapSourcePath = if ([string]::IsNullOrWhiteSpace($MapSourcePath)) {
  ''
} else {
  Resolve-SupportPath -PathValue $MapSourcePath -BaseDirectory $resolvedBackendWorkingDirectory -AllowMissing
}

if (-not [string]::IsNullOrWhiteSpace($resolvedBackendWorkingDirectory) -and -not (Test-Path $resolvedBackendWorkingDirectory)) {
  New-Item -ItemType Directory -Force -Path $resolvedBackendWorkingDirectory | Out-Null
}

foreach ($artifactPath in @($resolvedTrajectoryPath, $resolvedMapPath, $resolvedRuntimeLogPath)) {
  if ([string]::IsNullOrWhiteSpace($artifactPath)) {
    continue
  }

  $artifactDirectory = Split-Path -Parent $artifactPath
  if (-not [string]::IsNullOrWhiteSpace($artifactDirectory) -and -not (Test-Path $artifactDirectory)) {
    New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null
  }
}

$resolvedBackendArguments = @($resolvedVocabularyPath, $resolvedSettingsPath) + @($BackendArguments)
$playArguments = @(
  'ros2', 'bag', 'play',
  $resolvedBagPath.Replace('\', '/'),
  '-r', $PlaybackRate.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture)
)

Write-Host '[INFO] Preparing ORB-SLAM3 monocular backend run on top of bag playback.'
Write-Host "[INFO] experiment_name=$ExperimentName"
Write-Host "[INFO] bag_path=$resolvedBagPath"
Write-Host "[INFO] backend_command=$resolvedBackendCommand"
Write-Host "[INFO] backend_workdir=$resolvedBackendWorkingDirectory"
Write-Host "[INFO] trajectory_target=$resolvedTrajectoryPath"

if ($CheckOnly) {
  Write-Host '[INFO] CheckOnly=true, backend launch and bag playback were skipped.'
  Write-Host "[INFO] vocabulary_path=$resolvedVocabularyPath"
  Write-Host "[INFO] settings_path=$resolvedSettingsPath"
  Write-Host "[INFO] trajectory_source_path=$resolvedTrajectorySourcePath"
  Write-Host "[INFO] map_source_path=$resolvedMapSourcePath"
  Write-Host ('[INFO] ros2 bag play command=' + ($playArguments -join ' '))
  exit 0
}

$runtimeDirectory = Split-Path -Parent $resolvedRuntimeLogPath
$backendStdoutPath = Join-Path $runtimeDirectory 'orbslam3_backend_stdout.log'
$backendStderrPath = Join-Path $runtimeDirectory 'orbslam3_backend_stderr.log'
Remove-Item $backendStdoutPath, $backendStderrPath -ErrorAction SilentlyContinue

$backendProcess = $null
$backendForcedStop = $false
$backendExitCode = $null
$playbackSucceeded = $false
$trajectoryCopyStatus = '<trajectory_not_processed>'
$mapCopyStatus = '<map_not_processed>'
$capturedError = $null

try {
  # Start the topic-based backend before bag playback so it can initialize
  # vocabulary/settings and subscribe before the first frames are published.
  $backendProcess = Start-ManagedProcess `
    -CommandPath $resolvedBackendCommand `
    -Arguments $resolvedBackendArguments `
    -WorkingDirectory $resolvedBackendWorkingDirectory `
    -StdoutPath $backendStdoutPath `
    -StderrPath $backendStderrPath `
    -UseRosEnv:$UseRosEnvForBackend

  if ($StartupDelaySeconds -gt 0) {
    Start-Sleep -Seconds $StartupDelaySeconds
  }

  if ($backendProcess.HasExited) {
    $backendProcess.Refresh()
    $backendExitCode = $backendProcess.ExitCode
    if ($backendExitCode -ne 0) {
      throw "ORB-SLAM3 backend exited before bag playback started with code $backendExitCode."
    }
  }

  Invoke-RosEnvCommand `
    -EnvScript $envScript `
    -Arguments $playArguments `
    -PrintOutput `
    -FailureMessage 'ros2 bag play for ORB-SLAM3 failed.' | Out-Null
  $playbackSucceeded = $true

  if ($backendProcess -and -not $backendProcess.HasExited) {
    if (-not $backendProcess.WaitForExit($PostPlaybackGraceSeconds * 1000)) {
      $backendForcedStop = $true
      Stop-ProcessTree -Process $backendProcess -ProcessName 'orbslam3_backend'
    }
  }

  if ($backendProcess) {
    $backendProcess.Refresh()
    if ($backendProcess.HasExited) {
      $backendExitCode = $backendProcess.ExitCode
    }
  }

  if (-not $backendForcedStop -and $null -ne $backendExitCode -and $backendExitCode -ne 0) {
    throw "ORB-SLAM3 backend exited with code $backendExitCode."
  }

  $trajectoryCopyStatus = Copy-ArtifactIfPresent `
    -SourcePath $resolvedTrajectorySourcePath `
    -TargetPath $resolvedTrajectoryPath `
    -ArtifactName 'trajectory'
  $mapCopyStatus = Copy-ArtifactIfPresent `
    -SourcePath $resolvedMapSourcePath `
    -TargetPath $resolvedMapPath `
    -ArtifactName 'map'
}
catch {
  $capturedError = $_
  throw
}
finally {
  if ($backendProcess -and -not $backendProcess.HasExited) {
    $backendForcedStop = $true
    Stop-ProcessTree -Process $backendProcess -ProcessName 'orbslam3_backend'
  }
  if ($backendProcess) {
    try {
      $backendProcess.Refresh()
      if ($backendProcess.HasExited) {
        $backendExitCode = $backendProcess.ExitCode
      }
    }
    catch {
    }
  }

  $backendStdoutText = Read-OptionalUtf8File -Path $backendStdoutPath
  $backendStderrText = Read-OptionalUtf8File -Path $backendStderrPath
  $runtimeLines = @(
    'ORB-SLAM3 backend runtime log',
    "generated_at_utc=$((Get-Date).ToUniversalTime().ToString('o'))",
    "experiment_name=$ExperimentName",
    "bag_path=$resolvedBagPath",
    "backend_command=$resolvedBackendCommand",
    "backend_working_directory=$resolvedBackendWorkingDirectory",
    "vocabulary_path=$resolvedVocabularyPath",
    "settings_path=$resolvedSettingsPath",
    "playback_rate=$($PlaybackRate.ToString('0.0############', [System.Globalization.CultureInfo]::InvariantCulture))",
    "playback_succeeded=$playbackSucceeded",
    "backend_forced_stop=$backendForcedStop",
    "backend_exit_code=$(if ($null -eq $backendExitCode) { '<unknown>' } else { [string]$backendExitCode })",
    "trajectory_target=$resolvedTrajectoryPath",
    "trajectory_source=$resolvedTrajectorySourcePath",
    "trajectory_copy_status=$trajectoryCopyStatus",
    "map_target=$(if ([string]::IsNullOrWhiteSpace($resolvedMapPath)) { '<not_requested>' } else { $resolvedMapPath })",
    "map_source=$(if ([string]::IsNullOrWhiteSpace($resolvedMapSourcePath)) { '<not_configured>' } else { $resolvedMapSourcePath })",
    "map_copy_status=$mapCopyStatus",
    "last_error=$(if ($capturedError) { $capturedError.Exception.Message } else { '<none>' })",
    '',
    '--- STDOUT ---',
    $backendStdoutText,
    '',
    '--- STDERR ---',
    $backendStderrText
  )
  Write-Utf8TextFile -Path $resolvedRuntimeLogPath -Lines $runtimeLines
}

Write-Host '[INFO] ORB-SLAM3 backend orchestration completed.'
Write-Host "[INFO] runtime_log_path=$resolvedRuntimeLogPath"
if (Test-Path $resolvedTrajectoryPath) {
  Write-Host "[INFO] trajectory_path=$resolvedTrajectoryPath"
} else {
  Write-Host '[WARN] ORB-SLAM3 backend did not create trajectory at the expected location.'
}
if (-not [string]::IsNullOrWhiteSpace($resolvedMapPath) -and (Test-Path $resolvedMapPath)) {
  Write-Host "[INFO] map_path=$resolvedMapPath"
}

