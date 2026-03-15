Set-StrictMode -Version Latest

function Get-SlamExperimentManifestPath {
  param([string]$ExperimentRoot)

  return Join-Path $ExperimentRoot 'experiment_manifest.json'
}

function Get-SlamExperimentCatalogPath {
  param([string]$ExperimentsRoot)

  return Join-Path $ExperimentsRoot 'slam_experiment_catalog.json'
}

function Get-ObjectValue {
  param(
    $Object,
    [string[]]$PathSegments,
    $DefaultValue = $null
  )

  $current = $Object
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

function Resolve-SlamExperimentManifestPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw 'Путь до эксперимента пустой.'
  }

  $resolvedPath = (Resolve-Path $Path).Path
  $item = Get-Item -LiteralPath $resolvedPath
  if ($item.PSIsContainer) {
    $manifestPath = Get-SlamExperimentManifestPath -ExperimentRoot $item.FullName
    if (-not (Test-Path $manifestPath)) {
      throw "В каталоге эксперимента не найден experiment_manifest.json: $($item.FullName)"
    }
    return $manifestPath
  }

  if ($item.Extension -ne '.json') {
    throw "Ожидался JSON-манифест или каталог эксперимента, но получен файл: $($item.FullName)"
  }

  return $item.FullName
}

function Read-SlamExperimentManifest {
  param([string]$Path)

  $manifestPath = Resolve-SlamExperimentManifestPath -Path $Path
  return Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

function ConvertTo-SlamExperimentCatalogEntry {
  param([object]$Manifest)

  return [pscustomobject][ordered]@{
    experiment_name = $Manifest.experiment_name
    generated_at_utc = $Manifest.generated_at_utc
    dataset_name = $Manifest.dataset_name
    slam_backend = [string](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан')
    ready_for_slam = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false)
    preflight_success = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('preflight', 'success') -DefaultValue $false)
    feature_success = [bool](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'success') -DefaultValue $false)
    average_fps = [double](Get-ObjectValue -Object $Manifest -PathSegments @('preflight', 'average_fps') -DefaultValue 0.0)
    average_keypoints = [double](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'average_keypoints') -DefaultValue 0.0)
    average_coverage = [double](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'average_coverage') -DefaultValue 0.0)
    average_blur = [double](Get-ObjectValue -Object $Manifest -PathSegments @('feature_monitor', 'average_blur') -DefaultValue 0.0)
    tracking_lost = Get-ObjectValue -Object $Manifest -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null
    map_quality = [string](Get-ObjectValue -Object $Manifest -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
    experiment_root = $Manifest.experiment_root
    manifest_path = Get-SlamExperimentManifestPath -ExperimentRoot $Manifest.experiment_root
  }
}

function Update-SlamExperimentCatalogFile {
  param([string]$ExperimentsRoot)

  $catalogPath = Get-SlamExperimentCatalogPath -ExperimentsRoot $ExperimentsRoot
  $entries = @()

  if (-not (Test-Path $ExperimentsRoot)) {
    $catalog = [ordered]@{
      schema_version = 1
      generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
      experiment_count = 0
      experiments = @()
    }
    Set-Content -Path $catalogPath -Value ($catalog | ConvertTo-Json -Depth 6) -Encoding UTF8
    return $catalog
  }

  foreach ($experimentDirectory in (Get-ChildItem -Path $ExperimentsRoot -Directory | Sort-Object Name)) {
    $manifestPath = Get-SlamExperimentManifestPath -ExperimentRoot $experimentDirectory.FullName
    if (-not (Test-Path $manifestPath)) {
      continue
    }

    $manifest = Get-Content -Path $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries += ConvertTo-SlamExperimentCatalogEntry -Manifest $manifest
  }

  $orderedEntries = @($entries | Sort-Object generated_at_utc -Descending)
  $catalog = [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    experiment_count = $orderedEntries.Count
    experiments = $orderedEntries
  }

  Set-Content -Path $catalogPath -Value ($catalog | ConvertTo-Json -Depth 6) -Encoding UTF8
  return $catalog
}

function Get-ExperimentTrackingLostLabel {
  param($Value)

  if ($null -eq $Value) {
    return 'не_оценено'
  }
  if ([bool]$Value) {
    return 'да'
  }

  return 'нет'
}

function Get-MetricDelta {
  param(
    $BaselineValue,
    $CandidateValue,
    [int]$Precision = 2
  )

  if ($null -eq $BaselineValue -or $null -eq $CandidateValue) {
    return $null
  }

  try {
    return [Math]::Round(([double]$CandidateValue - [double]$BaselineValue), $Precision)
  }
  catch {
    return $null
  }
}

function New-MetricComparison {
  param(
    [string]$MetricName,
    $BaselineValue,
    $CandidateValue,
    [int]$Precision = 2
  )

  return [ordered]@{
    name = $MetricName
    baseline = $BaselineValue
    candidate = $CandidateValue
    delta = Get-MetricDelta -BaselineValue $BaselineValue -CandidateValue $CandidateValue -Precision $Precision
  }
}

function Compare-SlamExperimentManifests {
  param(
    [object]$BaselineManifest,
    [object]$CandidateManifest,
    [string]$BaselineManifestPath,
    [string]$CandidateManifestPath
  )

  $sameDataset = $BaselineManifest.dataset_name -eq $CandidateManifest.dataset_name
  $baselineReady = [bool](Get-ObjectValue -Object $BaselineManifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false)
  $candidateReady = [bool](Get-ObjectValue -Object $CandidateManifest -PathSegments @('experiment', 'ready_for_slam') -DefaultValue $false)

  $notes = @()
  if (-not $sameDataset) {
    $notes += 'Сравниваются эксперименты на разных датасетах, поэтому дельты метрик нужно трактовать осторожно.'
  }
  if ($baselineReady -and -not $candidateReady) {
    $notes += 'У кандидата наблюдается регрессия готовности к SLAM относительно baseline.'
  }
  if (-not $baselineReady -and $candidateReady) {
    $notes += 'Кандидат улучшил статус ready_for_slam относительно baseline.'
  }
  if ($notes.Count -eq 0) {
    $notes += 'Критичных регрессий на уровне входных метрик не обнаружено; сравните backend-результаты вручную.'
  }

  return [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    baseline = [ordered]@{
      experiment_name = $BaselineManifest.experiment_name
      dataset_name = $BaselineManifest.dataset_name
      slam_backend = [string](Get-ObjectValue -Object $BaselineManifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан')
      manifest_path = $BaselineManifestPath
      experiment_root = $BaselineManifest.experiment_root
    }
    candidate = [ordered]@{
      experiment_name = $CandidateManifest.experiment_name
      dataset_name = $CandidateManifest.dataset_name
      slam_backend = [string](Get-ObjectValue -Object $CandidateManifest -PathSegments @('experiment', 'slam_backend') -DefaultValue 'не_задан')
      manifest_path = $CandidateManifestPath
      experiment_root = $CandidateManifest.experiment_root
    }
    compatibility = [ordered]@{
      same_dataset = $sameDataset
      same_bag_root = $BaselineManifest.bag_root -eq $CandidateManifest.bag_root
    }
    readiness = [ordered]@{
      baseline_ready_for_slam = $baselineReady
      candidate_ready_for_slam = $candidateReady
      ready_for_slam_regressed = $baselineReady -and -not $candidateReady
      ready_for_slam_improved = (-not $baselineReady) -and $candidateReady
    }
    metrics = [ordered]@{
      average_fps = New-MetricComparison `
        -MetricName 'average_fps' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('preflight', 'average_fps') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('preflight', 'average_fps') -DefaultValue $null)
      average_keypoints = New-MetricComparison `
        -MetricName 'average_keypoints' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_keypoints') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_keypoints') -DefaultValue $null)
      average_coverage = New-MetricComparison `
        -MetricName 'average_coverage' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_coverage') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_coverage') -DefaultValue $null)
      average_blur = New-MetricComparison `
        -MetricName 'average_blur' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_blur') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_blur') -DefaultValue $null)
      average_brightness = New-MetricComparison `
        -MetricName 'average_brightness' `
        -BaselineValue (Get-ObjectValue -Object $BaselineManifest -PathSegments @('feature_monitor', 'average_brightness') -DefaultValue $null) `
        -CandidateValue (Get-ObjectValue -Object $CandidateManifest -PathSegments @('feature_monitor', 'average_brightness') -DefaultValue $null)
    }
    manual_assessment = [ordered]@{
      baseline_tracking_lost = Get-ObjectValue -Object $BaselineManifest -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null
      candidate_tracking_lost = Get-ObjectValue -Object $CandidateManifest -PathSegments @('manual_assessment', 'tracking_lost') -DefaultValue $null
      baseline_map_quality = [string](Get-ObjectValue -Object $BaselineManifest -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
      candidate_map_quality = [string](Get-ObjectValue -Object $CandidateManifest -PathSegments @('manual_assessment', 'map_quality') -DefaultValue 'не_оценено')
      baseline_subjective_notes = [string](Get-ObjectValue -Object $BaselineManifest -PathSegments @('manual_assessment', 'subjective_notes') -DefaultValue '')
      candidate_subjective_notes = [string](Get-ObjectValue -Object $CandidateManifest -PathSegments @('manual_assessment', 'subjective_notes') -DefaultValue '')
    }
    notes = $notes
  }
}
