Set-StrictMode -Version Latest

function Get-DatasetManifestPath {
  param([string]$DatasetRoot)

  return Join-Path $DatasetRoot 'dataset_manifest.json'
}

function Get-DatasetCatalogPath {
  param([string]$DatasetsRoot)

  return Join-Path $DatasetsRoot 'dataset_catalog.json'
}

function Get-GitSnapshot {
  param([string]$RepositoryRoot)

  $branch = 'unknown'
  $commit = 'unknown'

  try {
    $branchOutput = (& git -C $RepositoryRoot rev-parse --abbrev-ref HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $branchOutput) {
      $branch = ($branchOutput | Select-Object -Last 1).Trim()
    }

    $commitOutput = (& git -C $RepositoryRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $commitOutput) {
      $commit = ($commitOutput | Select-Object -Last 1).Trim()
    }
  }
  catch {
    # Если git временно недоступен, оставляем значения unknown и не ломаем весь workflow.
  }

  return [ordered]@{
    branch = $branch
    commit = $commit
  }
}

function ConvertFrom-RosBagInfoText {
  param([string]$BagInfoText)

  if ([string]::IsNullOrWhiteSpace($BagInfoText)) {
    throw 'Текст ros2 bag info пустой, невозможно построить summary.'
  }

  $summary = [ordered]@{
    files = @()
    bag_size_text = ''
    storage_id = ''
    ros_distro = ''
    duration_seconds = 0.0
    start_time_epoch_sec = 0.0
    end_time_epoch_sec = 0.0
    message_count_total = 0
    topics = @()
  }

  foreach ($line in ($BagInfoText -split "`r?`n")) {
    if ($line -match '^Files:\s+(.+)$') {
      $summary.files = ($matches[1] -split ',\s*') | Where-Object { $_ }
      continue
    }
    if ($line -match '^Bag size:\s+(.+)$') {
      $summary.bag_size_text = $matches[1].Trim()
      continue
    }
    if ($line -match '^Storage id:\s+(.+)$') {
      $summary.storage_id = $matches[1].Trim()
      continue
    }
    if ($line -match '^ROS Distro:\s+(.+)$') {
      $summary.ros_distro = $matches[1].Trim()
      continue
    }
    if ($line -match '^Duration:\s+([0-9\.]+)s$') {
      $summary.duration_seconds = [double]::Parse(
        $matches[1],
        [System.Globalization.CultureInfo]::InvariantCulture)
      continue
    }
    if ($line -match '^Start:\s+.+\(([0-9\.]+)\)$') {
      $summary.start_time_epoch_sec = [double]::Parse(
        $matches[1],
        [System.Globalization.CultureInfo]::InvariantCulture)
      continue
    }
    if ($line -match '^End:\s+.+\(([0-9\.]+)\)$') {
      $summary.end_time_epoch_sec = [double]::Parse(
        $matches[1],
        [System.Globalization.CultureInfo]::InvariantCulture)
      continue
    }
    if ($line -match '^Messages:\s+([0-9]+)$') {
      $summary.message_count_total = [int]$matches[1]
      continue
    }
    if ($line -match 'Topic:\s+([^\|]+?)\s+\|\s+Type:\s+([^\|]+?)\s+\|\s+Count:\s+([0-9]+)\s+\|\s+Serialization Format:\s+(.+)$') {
      $summary.topics += [ordered]@{
        name = $matches[1].Trim()
        type = $matches[2].Trim()
        count = [int]$matches[3]
        serialization_format = $matches[4].Trim()
      }
    }
  }

  return $summary
}

function Get-BagFileEntries {
  param([string]$BagRoot)

  if (-not (Test-Path $BagRoot)) {
    return @()
  }

  return @(Get-ChildItem -Path $BagRoot -File | Sort-Object Name | ForEach-Object {
    [ordered]@{
      name = $_.Name
      size_bytes = [int64]$_.Length
    }
  })
}

function Get-TopicCount {
  param(
    [object[]]$Topics,
    [string]$TopicName
  )

  $topic = $Topics | Where-Object { $_.name -eq $TopicName } | Select-Object -First 1
  if ($null -eq $topic) {
    return 0
  }

  return [int]$topic.count
}

function New-DatasetManifest {
  param(
    [string]$DatasetName,
    [string]$DatasetRoot,
    [string]$BagRoot,
    [string]$LogRoot,
    [object]$RecordingParameters,
    [string]$BagInfoText,
    [object]$GitSnapshot,
    [string]$ManifestSource = 'record'
  )

  $bagSummary = ConvertFrom-RosBagInfoText -BagInfoText $BagInfoText
  $bagFiles = Get-BagFileEntries -BagRoot $BagRoot
  $bagSizeBytes = 0
  foreach ($bagFile in $bagFiles) {
    $bagSizeBytes += [int64]$bagFile.size_bytes
  }

  # Манифест хранит всё, что нужно для воспроизводимого offline-SLAM прогона:
  # параметры захвата, bag summary, git-снимок и пути до логов.
  return [ordered]@{
    schema_version = 1
    manifest_source = $ManifestSource
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    dataset_name = $DatasetName
    dataset_root = $DatasetRoot
    bag_root = $BagRoot
    log_root = $LogRoot
    git = [ordered]@{
      branch = $GitSnapshot.branch
      commit = $GitSnapshot.commit
    }
    recording = [ordered]@{
      duration_seconds = if ($RecordingParameters.duration_seconds) {
        $RecordingParameters.duration_seconds
      } else {
        $bagSummary.duration_seconds
      }
      startup_delay_seconds = $RecordingParameters.startup_delay_seconds
      device_index = $RecordingParameters.device_index
      width = $RecordingParameters.width
      height = $RecordingParameters.height
      fps = $RecordingParameters.fps
      frame_id = $RecordingParameters.frame_id
      calibration_file = $RecordingParameters.calibration_file
      storage_id = if ($RecordingParameters.storage_id) {
        $RecordingParameters.storage_id
      } else {
        $bagSummary.storage_id
      }
      use_msmf_requested = $RecordingParameters.use_msmf_requested
      use_msmf_selected = $RecordingParameters.use_msmf_selected
    }
    rosbag = [ordered]@{
      files = $bagFiles
      bag_size_bytes = [int64]$bagSizeBytes
      bag_size_text = $bagSummary.bag_size_text
      storage_id = $bagSummary.storage_id
      ros_distro = $bagSummary.ros_distro
      duration_seconds = $bagSummary.duration_seconds
      start_time_epoch_sec = $bagSummary.start_time_epoch_sec
      end_time_epoch_sec = $bagSummary.end_time_epoch_sec
      message_count_total = $bagSummary.message_count_total
      topics = $bagSummary.topics
    }
  }
}

function Get-SyntheticRecordingParametersFromLogs {
  param([string]$LogRoot)

  $parameters = [ordered]@{
    duration_seconds = 0
    startup_delay_seconds = 0
    device_index = 0
    width = 0
    height = 0
    fps = 0.0
    frame_id = ''
    calibration_file = ''
    storage_id = ''
    use_msmf_requested = $null
    use_msmf_selected = $null
  }

  $cameraLogPath = Join-Path $LogRoot 'camera_slam_ready_stdout.log'
  if (-not (Test-Path $cameraLogPath)) {
    return $parameters
  }

  $cameraLogs = Get-Content -Path $cameraLogPath -Raw -Encoding UTF8
  $startupMatch = [regex]::Match(
    $cameraLogs,
    'device_index=([0-9]+)\s+width=([0-9]+)\s+height=([0-9]+)\s+fps=([0-9\.]+)\s+frame_id=([^\s]+).+use_msmf=(true|false)')
  if ($startupMatch.Success) {
    $parameters.device_index = [int]$startupMatch.Groups[1].Value
    $parameters.width = [int]$startupMatch.Groups[2].Value
    $parameters.height = [int]$startupMatch.Groups[3].Value
    $parameters.fps = [double]::Parse($startupMatch.Groups[4].Value, [System.Globalization.CultureInfo]::InvariantCulture)
    $parameters.frame_id = $startupMatch.Groups[5].Value
    $useMsmf = $startupMatch.Groups[6].Value -eq 'true'
    $parameters.use_msmf_requested = $useMsmf
    $parameters.use_msmf_selected = $useMsmf
  }

  $calibrationMatch = [regex]::Match(
    $cameraLogs,
    'calibration_file=([A-Za-z]:/[^ \r\n]+\.yaml)')
  if ($calibrationMatch.Success) {
    $parameters.calibration_file = $calibrationMatch.Groups[1].Value
  }

  return $parameters
}

function Save-DatasetManifest {
  param(
    [object]$Manifest,
    [string]$ManifestPath
  )

  $manifestJson = $Manifest | ConvertTo-Json -Depth 8
  Set-Content -Path $ManifestPath -Value $manifestJson -Encoding UTF8
}

function ConvertTo-DatasetCatalogEntry {
  param([object]$Manifest)

  $topics = @($Manifest.rosbag.topics)
  return [pscustomobject][ordered]@{
    dataset_name = $Manifest.dataset_name
    generated_at_utc = $Manifest.generated_at_utc
    storage_id = $Manifest.rosbag.storage_id
    duration_seconds = $Manifest.rosbag.duration_seconds
    message_count_total = $Manifest.rosbag.message_count_total
    image_messages = Get-TopicCount -Topics $topics -TopicName '/camera/image_raw'
    camera_info_messages = Get-TopicCount -Topics $topics -TopicName '/camera/camera_info'
    tf_static_messages = Get-TopicCount -Topics $topics -TopicName '/tf_static'
    width = $Manifest.recording.width
    height = $Manifest.recording.height
    fps = $Manifest.recording.fps
    use_msmf_selected = $Manifest.recording.use_msmf_selected
    calibration_file = $Manifest.recording.calibration_file
    dataset_root = $Manifest.dataset_root
    bag_root = $Manifest.bag_root
    manifest_path = Get-DatasetManifestPath -DatasetRoot $Manifest.dataset_root
  }
}

function Update-DatasetCatalogFile {
  param(
    [string]$DatasetsRoot,
    [string]$RepositoryRoot = ''
  )

  $entries = @()
  $catalogPath = Get-DatasetCatalogPath -DatasetsRoot $DatasetsRoot

  if (-not (Test-Path $DatasetsRoot)) {
    $catalog = [ordered]@{
      schema_version = 1
      generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
      dataset_count = 0
      datasets = @()
    }
    Set-Content -Path $catalogPath -Value ($catalog | ConvertTo-Json -Depth 6) -Encoding UTF8
    return $catalog
  }

  foreach ($datasetDirectory in (Get-ChildItem -Path $DatasetsRoot -Directory | Sort-Object Name)) {
    $manifestPath = Get-DatasetManifestPath -DatasetRoot $datasetDirectory.FullName
    if (-not (Test-Path $manifestPath)) {
      $bagRoot = Join-Path $datasetDirectory.FullName 'bag'
      $logRoot = Join-Path $datasetDirectory.FullName 'logs'
      $bagInfoPath = Join-Path $logRoot 'rosbag_info.txt'

      if ((Test-Path $bagRoot) -and (Test-Path $bagInfoPath)) {
        $recordingParameters = Get-SyntheticRecordingParametersFromLogs -LogRoot $logRoot
        $gitSnapshot = if ($RepositoryRoot) {
          Get-GitSnapshot -RepositoryRoot $RepositoryRoot
        } else {
          [ordered]@{
            branch = 'unknown'
            commit = 'unknown'
          }
        }
        $syntheticManifest = New-DatasetManifest `
          -DatasetName $datasetDirectory.Name `
          -DatasetRoot $datasetDirectory.FullName `
          -BagRoot $bagRoot `
          -LogRoot $logRoot `
          -RecordingParameters $recordingParameters `
          -BagInfoText (Get-Content -Path $bagInfoPath -Raw -Encoding UTF8) `
          -GitSnapshot $gitSnapshot `
          -ManifestSource 'catalog_rebuild'
        Save-DatasetManifest -Manifest $syntheticManifest -ManifestPath $manifestPath
      }
    }

    if (-not (Test-Path $manifestPath)) {
      continue
    }

    $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries += ConvertTo-DatasetCatalogEntry -Manifest $manifest
  }

  $orderedEntries = @($entries | Sort-Object generated_at_utc -Descending)
  $catalog = [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    dataset_count = $orderedEntries.Count
    datasets = $orderedEntries
  }

  Set-Content -Path $catalogPath -Value ($catalog | ConvertTo-Json -Depth 6) -Encoding UTF8
  return $catalog
}

