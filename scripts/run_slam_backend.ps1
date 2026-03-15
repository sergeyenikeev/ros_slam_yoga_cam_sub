[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$ExperimentPath,
  [string]$ConfigFile = '',
  [string]$BackendName = '',
  [string]$Command = '',
  [string[]]$ArgumentTemplate = @(),
  [string]$WorkingDirectory = '',
  [int]$TimeoutSeconds = 0,
  [string]$TrajectoryPath = '',
  [string]$MapPath = '',
  [string]$RuntimeLogPath = '',
  [string]$ResultNotes = '',
  [switch]$AllowFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$packageRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'process_utils.ps1')
. (Join-Path $PSScriptRoot 'slam_experiment_utils.ps1')
. (Join-Path $PSScriptRoot 'trajectory_report_utils.ps1')

function Get-ConfigValue {
  param(
    $Config,
    [string[]]$PathSegments,
    $DefaultValue
  )

  if ($null -eq $Config) {
    return $DefaultValue
  }

  $current = $Config
  foreach ($segment in $PathSegments) {
    if ($null -eq $current) {
      return $DefaultValue
    }

    $property = $current.PSObject.Properties[$segment]
    if (-not $property) {
      return $DefaultValue
    }

    $current = $property.Value
  }

  if ($null -eq $current) {
    return $DefaultValue
  }
  if ($current -is [string] -and [string]::IsNullOrWhiteSpace($current)) {
    return $DefaultValue
  }

  return $current
}

function Expand-TemplateString {
  param(
    [string]$Value,
    [hashtable]$Context
  )

  if ([string]::IsNullOrWhiteSpace($Value)) {
    return $Value
  }

  $expanded = $Value
  foreach ($key in ($Context.Keys | Sort-Object Length -Descending)) {
    $expanded = $expanded.Replace('{' + $key + '}', [string]$Context[$key])
  }

  return $expanded
}

function Resolve-CommandPath {
  param(
    [string]$PathValue,
    [string]$ExperimentRoot
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return $PathValue
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }

  $packageCandidate = Join-Path $packageRoot $PathValue
  if (Test-Path $packageCandidate) {
    return (Resolve-Path $packageCandidate).Path
  }

  $experimentCandidate = Join-Path $ExperimentRoot $PathValue
  if (Test-Path $experimentCandidate) {
    return (Resolve-Path $experimentCandidate).Path
  }

  return $PathValue
}

function Resolve-WorkingDirectoryPath {
  param(
    [string]$PathValue,
    [string]$ExperimentRoot
  )

  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return $ExperimentRoot
  }
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return $PathValue
  }

  $packageCandidate = Join-Path $packageRoot $PathValue
  if (Test-Path $packageCandidate) {
    return (Resolve-Path $packageCandidate).Path
  }

  return Join-Path $ExperimentRoot $PathValue
}

function Write-Utf8File {
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

function ConvertTo-PowerShellLiteral {
  param([string]$Value)

  return "'" + ($Value -replace "'", "''") + "'"
}

$manifestPath = Resolve-SlamExperimentManifestPath -Path $ExperimentPath
$experimentRoot = Split-Path -Parent $manifestPath
$summaryPath = Get-SlamExperimentSummaryPath -ExperimentRoot $experimentRoot
$manifest = Read-SlamExperimentManifest -Path $manifestPath

$resolvedConfigPath = ''
if ([string]::IsNullOrWhiteSpace($ConfigFile)) {
  $manifestConfig = [string](Get-ObjectValue -Object $manifest -PathSegments @('experiment', 'config_file') -DefaultValue '')
  if (-not [string]::IsNullOrWhiteSpace($manifestConfig)) {
    $ConfigFile = $manifestConfig
  }
}
if (-not [string]::IsNullOrWhiteSpace($ConfigFile)) {
  $resolvedConfigPath = if ([System.IO.Path]::IsPathRooted($ConfigFile)) {
    $ConfigFile
  } else {
    Join-Path $packageRoot $ConfigFile
  }
  if (-not (Test-Path $resolvedConfigPath)) {
    throw "Файл конфигурации backend runner не найден: $resolvedConfigPath"
  }
}

$config = $null
if (-not [string]::IsNullOrWhiteSpace($resolvedConfigPath)) {
  $config = Get-Content -Path $resolvedConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$backendConfig = if ($config -and $config.PSObject.Properties['backend_runner']) {
  $config.backend_runner
} else {
  $config
}

$effectiveBackendName = if (-not [string]::IsNullOrWhiteSpace($BackendName)) {
  $BackendName
} else {
  [string](Get-ConfigValue -Config $backendConfig -PathSegments @('backend_name') -DefaultValue (Get-ObjectValue -Object $manifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан'))
}
$effectiveCommandTemplate = if (-not [string]::IsNullOrWhiteSpace($Command)) {
  $Command
} else {
  [string](Get-ConfigValue -Config $backendConfig -PathSegments @('command') -DefaultValue '')
}
$effectiveArgumentTemplates = if ($ArgumentTemplate.Count -gt 0) {
  @($ArgumentTemplate)
} else {
  @((Get-ConfigValue -Config $backendConfig -PathSegments @('arguments') -DefaultValue @()))
}
$effectiveWorkingDirectoryTemplate = if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
  $WorkingDirectory
} else {
  [string](Get-ConfigValue -Config $backendConfig -PathSegments @('working_directory') -DefaultValue '{experiment_root}')
}
$effectiveTimeoutSeconds = if ($TimeoutSeconds -gt 0) {
  $TimeoutSeconds
} else {
  [int](Get-ConfigValue -Config $backendConfig -PathSegments @('timeout_seconds') -DefaultValue 0)
}
$effectiveTrajectoryPathTemplate = if (-not [string]::IsNullOrWhiteSpace($TrajectoryPath)) {
  $TrajectoryPath
} else {
  [string](Get-ConfigValue -Config $backendConfig -PathSegments @('trajectory_path') -DefaultValue '')
}
$effectiveTrajectoryFormat = [string](Get-ConfigValue -Config $backendConfig -PathSegments @('trajectory_format') -DefaultValue '')
$effectiveMapPathTemplate = if (-not [string]::IsNullOrWhiteSpace($MapPath)) {
  $MapPath
} else {
  [string](Get-ConfigValue -Config $backendConfig -PathSegments @('map_path') -DefaultValue '')
}
$effectiveRuntimeLogPathTemplate = if (-not [string]::IsNullOrWhiteSpace($RuntimeLogPath)) {
  $RuntimeLogPath
} else {
  [string](Get-ConfigValue -Config $backendConfig -PathSegments @('runtime_log_path') -DefaultValue '')
}
$effectiveResultNotes = if (-not [string]::IsNullOrWhiteSpace($ResultNotes)) {
  $ResultNotes
} else {
  [string](Get-ConfigValue -Config $backendConfig -PathSegments @('result_notes') -DefaultValue '')
}
$effectiveAllowFailure = if ($AllowFailure.IsPresent) {
  $true
} else {
  [bool](Get-ConfigValue -Config $backendConfig -PathSegments @('allow_failure') -DefaultValue $false)
}

if ([string]::IsNullOrWhiteSpace($effectiveCommandTemplate)) {
  throw 'Не задан command для backend runner.'
}

$backendRoot = Join-Path $experimentRoot 'backend_artifacts'
New-Item -ItemType Directory -Force -Path $backendRoot | Out-Null
$stdoutLogPath = Join-Path $backendRoot 'backend_stdout.log'
$stderrLogPath = Join-Path $backendRoot 'backend_stderr.log'

# Весь runtime backend привязываем к единому templateContext, чтобы один и тот же
# config-шаблон можно было воспроизводимо запускать на разных experiment packet.
$templateContext = @{
  experiment_root = $experimentRoot
  experiment_name = $manifest.experiment_name
  dataset_root = $manifest.dataset_root
  dataset_name = $manifest.dataset_name
  bag_root = $manifest.bag_root
  reports_root = Join-Path $experimentRoot 'reports'
  backend_root = $backendRoot
  trajectory_path = Resolve-ExperimentArtifactPath -ExperimentRoot $experimentRoot -PathValue (Expand-TemplateString -Value $effectiveTrajectoryPathTemplate -Context @{
    experiment_root = $experimentRoot
    backend_root = $backendRoot
  })
  map_path = Resolve-ExperimentArtifactPath -ExperimentRoot $experimentRoot -PathValue (Expand-TemplateString -Value $effectiveMapPathTemplate -Context @{
    experiment_root = $experimentRoot
    backend_root = $backendRoot
  })
  runtime_log_path = Resolve-ExperimentArtifactPath -ExperimentRoot $experimentRoot -PathValue (Expand-TemplateString -Value $effectiveRuntimeLogPathTemplate -Context @{
    experiment_root = $experimentRoot
    backend_root = $backendRoot
  })
  stdout_log_path = $stdoutLogPath
  stderr_log_path = $stderrLogPath
}

$resolvedCommandTemplate = Expand-TemplateString -Value $effectiveCommandTemplate -Context $templateContext
$resolvedArgumentValues = @()
foreach ($argumentTemplateValue in $effectiveArgumentTemplates) {
  $resolvedArgumentValues += (Expand-TemplateString -Value ([string]$argumentTemplateValue) -Context $templateContext)
}
$resolvedWorkingDirectory = Resolve-WorkingDirectoryPath `
  -PathValue (Expand-TemplateString -Value $effectiveWorkingDirectoryTemplate -Context $templateContext) `
  -ExperimentRoot $experimentRoot

foreach ($artifactPath in @($templateContext.trajectory_path, $templateContext.map_path, $templateContext.runtime_log_path, $stdoutLogPath, $stderrLogPath)) {
  if ([string]::IsNullOrWhiteSpace($artifactPath)) {
    continue
  }

  $artifactDirectory = Split-Path -Parent $artifactPath
  if (-not [string]::IsNullOrWhiteSpace($artifactDirectory) -and -not (Test-Path $artifactDirectory)) {
    New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null
  }
}

$resolvedCommandPath = Resolve-CommandPath -PathValue $resolvedCommandTemplate -ExperimentRoot $experimentRoot
$invocationFile = $resolvedCommandPath
$invocationArguments = @()

if ([System.IO.Path]::GetExtension($resolvedCommandPath).ToLowerInvariant() -eq '.ps1') {
  # Для PowerShell-backend принудительно включаем UTF-8 вывод, чтобы диагностические
  # сообщения в логах и stdout runner оставались читаемыми в Windows-конвейере.
  $scriptInvocation = '& ' + (ConvertTo-PowerShellLiteral -Value $resolvedCommandPath)
  foreach ($argumentValue in $resolvedArgumentValues) {
    $argumentText = [string]$argumentValue
    if ($argumentText -match '^-[A-Za-z0-9_:-]+$') {
      $scriptInvocation += ' ' + $argumentText
    } else {
      $scriptInvocation += ' ' + (ConvertTo-PowerShellLiteral -Value $argumentText)
    }
  }

  $commandText = "[Console]::InputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
    "[Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8; " +
    $scriptInvocation + '; exit $LASTEXITCODE'

  $invocationFile = 'powershell.exe'
  $invocationArguments += @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $commandText)
} else {
  $invocationArguments += $resolvedArgumentValues
}

Write-Host '[ИНФО] Запускаем внешний monocular SLAM backend.'
Write-Host "[ИНФО] experiment_root=$experimentRoot"
Write-Host "[ИНФО] backend_name=$effectiveBackendName"
Write-Host "[ИНФО] command=$resolvedCommandPath"

$startedAt = Get-Date
$processResult = Invoke-LoggedProcess `
  -FilePath $invocationFile `
  -ArgumentList $invocationArguments `
  -WorkingDirectory $resolvedWorkingDirectory `
  -TimeoutSeconds $effectiveTimeoutSeconds `
  -PrintOutput `
  -AllowNonZeroExit
$finishedAt = Get-Date
$durationSeconds = [Math]::Round(($finishedAt - $startedAt).TotalSeconds, 3)

Write-Utf8File -Path $stdoutLogPath -Lines $processResult.StdOutLines
Write-Utf8File -Path $stderrLogPath -Lines $processResult.StdErrLines

$trajectoryFound = (-not [string]::IsNullOrWhiteSpace($templateContext.trajectory_path)) -and (Test-Path $templateContext.trajectory_path)
$mapFound = (-not [string]::IsNullOrWhiteSpace($templateContext.map_path)) -and (Test-Path $templateContext.map_path)
$runtimeLogFound = (-not [string]::IsNullOrWhiteSpace($templateContext.runtime_log_path)) -and (Test-Path $templateContext.runtime_log_path)
$trajectoryReportPath = Get-TrajectoryReportPath -ExperimentRoot $experimentRoot
$trajectorySummaryPath = Get-TrajectorySummaryPath -ExperimentRoot $experimentRoot
$trajectoryAnalysis = [ordered]@{
  success = $false
  format = $effectiveTrajectoryFormat
  report_path = ''
  summary_path = ''
  error_message = ''
}

if ($trajectoryFound) {
  # Даже если runner сам завершился с кодом 0, отсутствие нормализованного
  # trajectory-report считаем проблемой: без него baseline/candidate сравнивать сложнее.
  if ([string]::IsNullOrWhiteSpace($effectiveTrajectoryFormat)) {
    $trajectoryAnalysis.error_message = 'Для найденного trajectory не задан trajectory_format в конфигурации backend runner.'
    Write-Host "[ПРЕДУПРЕЖДЕНИЕ] $($trajectoryAnalysis.error_message)"
  } elseif ($effectiveTrajectoryFormat -eq 'csv_pose_v1') {
    try {
      # Trajectory переводим в единый отчёт сразу после backend run, чтобы
      # сравнение экспериментов не зависело от конкретного backend и его логов.
      $trajectorySamples = Read-CsvPoseV1Trajectory -Path $templateContext.trajectory_path
      $trajectoryReport = Measure-CsvPoseV1Trajectory `
        -Samples $trajectorySamples `
        -TrajectoryPath $templateContext.trajectory_path `
        -BackendName $effectiveBackendName
      Write-TrajectoryReportArtifacts `
        -TrajectoryReport $trajectoryReport `
        -ReportPath $trajectoryReportPath `
        -SummaryPath $trajectorySummaryPath

      $trajectoryAnalysis = [ordered]@{
        success = $true
        format = $effectiveTrajectoryFormat
        report_path = $trajectoryReportPath
        summary_path = $trajectorySummaryPath
        error_message = ''
        metrics = $trajectoryReport
      }
    }
    catch {
      $trajectoryAnalysis.error_message = $_.Exception.Message
      Write-Host "[ПРЕДУПРЕЖДЕНИЕ] Не удалось построить trajectory report: $($trajectoryAnalysis.error_message)"
    }
  } else {
    $trajectoryAnalysis.error_message = "Неподдерживаемый trajectory_format '$effectiveTrajectoryFormat'."
    Write-Host "[ПРЕДУПРЕЖДЕНИЕ] $($trajectoryAnalysis.error_message)"
  }
}

$expectedArtifactsOkay = $true
foreach ($artifactCheck in @(
  @{ Name = 'trajectory'; Path = $templateContext.trajectory_path; Found = $trajectoryFound },
  @{ Name = 'map'; Path = $templateContext.map_path; Found = $mapFound },
  @{ Name = 'runtime_log'; Path = $templateContext.runtime_log_path; Found = $runtimeLogFound }
)) {
  if (-not [string]::IsNullOrWhiteSpace($artifactCheck.Path) -and -not $artifactCheck.Found) {
    $expectedArtifactsOkay = $false
    Write-Host "[ПРЕДУПРЕЖДЕНИЕ] Backend не создал ожидаемый артефакт $($artifactCheck.Name): $($artifactCheck.Path)"
  }
}
if ($trajectoryFound -and -not $trajectoryAnalysis.success) {
  $expectedArtifactsOkay = $false
}

$backendRunSuccess = (-not $processResult.TimedOut) -and ($processResult.ExitCode -eq 0) -and $expectedArtifactsOkay
$manifest.experiment.slam_backend = $effectiveBackendName
# Manifest сохраняет не только факт запуска backend, но и нормализованную
# аналитическую сводку, чтобы compare/catalog не читали сырые backend-логи повторно.
$manifest.backend_result = [ordered]@{
  trajectory_path = $templateContext.trajectory_path
  map_path = $templateContext.map_path
  runtime_log_path = $templateContext.runtime_log_path
  result_notes = $effectiveResultNotes
  runner = [ordered]@{
    backend_name = $effectiveBackendName
    command = $resolvedCommandTemplate
    invocation_file = $invocationFile
    arguments = $resolvedArgumentValues
    working_directory = $resolvedWorkingDirectory
    timeout_seconds = $effectiveTimeoutSeconds
    trajectory_format = $effectiveTrajectoryFormat
    allow_failure = $effectiveAllowFailure
    started_at_utc = $startedAt.ToUniversalTime().ToString('o')
    finished_at_utc = $finishedAt.ToUniversalTime().ToString('o')
    duration_seconds = $durationSeconds
    exit_code = $processResult.ExitCode
    timed_out = $processResult.TimedOut
    success = $backendRunSuccess
    stdout_log_path = $stdoutLogPath
    stderr_log_path = $stderrLogPath
  }
  artifacts = [ordered]@{
    trajectory_found = $trajectoryFound
    map_found = $mapFound
    runtime_log_found = $runtimeLogFound
  }
  analysis = [ordered]@{
    trajectory = $trajectoryAnalysis
  }
}

$backendResultPath = Join-Path $backendRoot 'backend_result.json'
Set-Content -Path $backendResultPath -Value ($manifest.backend_result | ConvertTo-Json -Depth 8) -Encoding UTF8
Save-SlamExperimentManifest -Manifest $manifest -ManifestPath $manifestPath
Write-SlamExperimentSummary -Manifest $manifest -SummaryPath $summaryPath
$catalog = Update-SlamExperimentCatalogFile -ExperimentsRoot (Split-Path -Parent $experimentRoot)
$catalogPath = Get-SlamExperimentCatalogPath -ExperimentsRoot (Split-Path -Parent $experimentRoot)
$catalogMarkdownPath = Get-SlamExperimentCatalogMarkdownPath -ExperimentsRoot (Split-Path -Parent $experimentRoot)
$catalogCsvPath = Get-SlamExperimentCatalogCsvPath -ExperimentsRoot (Split-Path -Parent $experimentRoot)

Write-Host '[ИНФО] Результат backend runner сохранён в experiment packet.'
Write-Host "[ИНФО] backend_result_path=$backendResultPath"
Write-Host "[ИНФО] catalog_path=$catalogPath"
Write-Host "[ИНФО] catalog_markdown_path=$catalogMarkdownPath"
Write-Host "[ИНФО] catalog_csv_path=$catalogCsvPath"
Write-Host "[ИНФО] experiment_count=$($catalog.experiment_count)"

if (-not $backendRunSuccess -and -not $effectiveAllowFailure) {
  throw 'Внешний monocular SLAM backend завершился неуспешно.'
}


