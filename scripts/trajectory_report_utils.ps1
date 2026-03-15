Set-StrictMode -Version Latest

function Get-TrajectoryReportPath {
  param([string]$ExperimentRoot)

  return Join-Path $ExperimentRoot 'reports\trajectory_report.json'
}

function Get-TrajectorySummaryPath {
  param([string]$ExperimentRoot)

  return Join-Path $ExperimentRoot 'reports\trajectory_report.md'
}

function ConvertTo-InvariantDouble {
  param(
    [string]$Value,
    [string]$FieldName,
    [int]$RowNumber
  )

  try {
    return [double]::Parse(
      $Value,
      [System.Globalization.NumberStyles]::Float -bor [System.Globalization.NumberStyles]::AllowThousands,
      [System.Globalization.CultureInfo]::InvariantCulture)
  }
  catch {
    throw "Не удалось разобрать поле '$FieldName' в строке trajectory CSV #${RowNumber}: '$Value'."
  }
}

function Read-CsvPoseV1Trajectory {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    throw "Файл trajectory не найден: $Path"
  }

  $rows = @(Import-Csv -Path $Path)
  if ($rows.Count -eq 0) {
    throw "Файл trajectory пустой: $Path"
  }

  $requiredColumns = @('timestamp_sec', 'x', 'y', 'z')
  foreach ($columnName in $requiredColumns) {
    if (-not $rows[0].PSObject.Properties[$columnName]) {
      throw "Файл trajectory не содержит обязательную колонку '$columnName': $Path"
    }
  }

  $samples = [System.Collections.Generic.List[object]]::new()
  $rowNumber = 0
  foreach ($row in $rows) {
    $rowNumber++

    # Для experiment workflow используем минимальный и стабильный контракт:
    # timestamp + позиция камеры. Этого уже достаточно, чтобы автоматически
    # сравнивать длину траектории, смещение и среднюю скорость между прогонами
    # без привязки к внутреннему формату конкретного backend.
    $samples.Add([pscustomobject][ordered]@{
        timestamp_sec = ConvertTo-InvariantDouble -Value ([string]$row.timestamp_sec) -FieldName 'timestamp_sec' -RowNumber $rowNumber
        x = ConvertTo-InvariantDouble -Value ([string]$row.x) -FieldName 'x' -RowNumber $rowNumber
        y = ConvertTo-InvariantDouble -Value ([string]$row.y) -FieldName 'y' -RowNumber $rowNumber
        z = ConvertTo-InvariantDouble -Value ([string]$row.z) -FieldName 'z' -RowNumber $rowNumber
      })
  }

  return ,([object[]]$samples.ToArray())
}

function Measure-CsvPoseV1Trajectory {
  param(
    [object[]]$Samples,
    [string]$TrajectoryPath,
    [string]$BackendName
  )

  if (-not $Samples -or $Samples.Count -eq 0) {
    throw 'Для анализа trajectory не получено ни одной точки.'
  }

  $sampleCount = $Samples.Count
  $startPose = $Samples[0]
  $endPose = $Samples[$sampleCount - 1]
  $durationSec = [Math]::Round(($endPose.timestamp_sec - $startPose.timestamp_sec), 6)
  if ($sampleCount -gt 1 -and $durationSec -le 0.0) {
    throw 'Timestamp в trajectory должны строго возрастать.'
  }

  $minX = $startPose.x
  $maxX = $startPose.x
  $minY = $startPose.y
  $maxY = $startPose.y
  $minZ = $startPose.z
  $maxZ = $startPose.z
  $pathLength = 0.0
  $maxStep = 0.0

  # Идём по trajectory так, чтобы одновременно посчитать суммарную длину пути,
  # максимальный шаг между соседними позами и пространственные границы сцены.
  for ($index = 1; $index -lt $sampleCount; $index++) {
    $previous = $Samples[$index - 1]
    $current = $Samples[$index]

    if ($current.timestamp_sec -le $previous.timestamp_sec) {
      throw "Timestamp в trajectory должны строго возрастать. Нарушение обнаружено на шаге #$index."
    }

    $dx = $current.x - $previous.x
    $dy = $current.y - $previous.y
    $dz = $current.z - $previous.z
    $stepLength = [Math]::Sqrt(($dx * $dx) + ($dy * $dy) + ($dz * $dz))
    $pathLength += $stepLength
    if ($stepLength -gt $maxStep) {
      $maxStep = $stepLength
    }

    if ($current.x -lt $minX) { $minX = $current.x }
    if ($current.x -gt $maxX) { $maxX = $current.x }
    if ($current.y -lt $minY) { $minY = $current.y }
    if ($current.y -gt $maxY) { $maxY = $current.y }
    if ($current.z -lt $minZ) { $minZ = $current.z }
    if ($current.z -gt $maxZ) { $maxZ = $current.z }
  }

  $netDx = $endPose.x - $startPose.x
  $netDy = $endPose.y - $startPose.y
  $netDz = $endPose.z - $startPose.z
  $netDisplacement = [Math]::Sqrt(($netDx * $netDx) + ($netDy * $netDy) + ($netDz * $netDz))
  $meanStep = if ($sampleCount -gt 1) {
    $pathLength / ($sampleCount - 1)
  } else {
    0.0
  }
  $meanSpeed = if ($durationSec -gt 0.0) {
    $pathLength / $durationSec
  } else {
    0.0
  }

  return [ordered]@{
    schema_version = 1
    generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    backend_name = $BackendName
    trajectory_path = $TrajectoryPath
    trajectory_format = 'csv_pose_v1'
    sample_count = $sampleCount
    duration_sec = [Math]::Round($durationSec, 6)
    path_length_m = [Math]::Round($pathLength, 6)
    net_displacement_m = [Math]::Round($netDisplacement, 6)
    mean_step_m = [Math]::Round($meanStep, 6)
    max_step_m = [Math]::Round($maxStep, 6)
    mean_speed_mps = [Math]::Round($meanSpeed, 6)
    bounding_box = [ordered]@{
      min_x = [Math]::Round($minX, 6)
      max_x = [Math]::Round($maxX, 6)
      min_y = [Math]::Round($minY, 6)
      max_y = [Math]::Round($maxY, 6)
      min_z = [Math]::Round($minZ, 6)
      max_z = [Math]::Round($maxZ, 6)
      span_x = [Math]::Round($maxX - $minX, 6)
      span_y = [Math]::Round($maxY - $minY, 6)
      span_z = [Math]::Round($maxZ - $minZ, 6)
    }
    start_pose = [ordered]@{
      timestamp_sec = [Math]::Round($startPose.timestamp_sec, 6)
      x = [Math]::Round($startPose.x, 6)
      y = [Math]::Round($startPose.y, 6)
      z = [Math]::Round($startPose.z, 6)
    }
    end_pose = [ordered]@{
      timestamp_sec = [Math]::Round($endPose.timestamp_sec, 6)
      x = [Math]::Round($endPose.x, 6)
      y = [Math]::Round($endPose.y, 6)
      z = [Math]::Round($endPose.z, 6)
    }
  }
}

function Write-TrajectoryReportArtifacts {
  param(
    [object]$TrajectoryReport,
    [string]$ReportPath,
    [string]$SummaryPath
  )

  # Держим и JSON, и Markdown: JSON удобен для машинного сравнения,
  # Markdown — для быстрого ручного просмотра прямо в experiment packet.
  $reportDirectory = Split-Path -Parent $ReportPath
  if (-not (Test-Path $reportDirectory)) {
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
  }

  Set-Content -Path $ReportPath -Value ($TrajectoryReport | ConvertTo-Json -Depth 8) -Encoding UTF8

  $summaryLines = @(
    '# Отчёт по trajectory monocular SLAM backend',
    '',
    "- backend_name: $($TrajectoryReport.backend_name)",
    "- trajectory_path: $($TrajectoryReport.trajectory_path)",
    "- trajectory_format: $($TrajectoryReport.trajectory_format)",
    "- sample_count: $($TrajectoryReport.sample_count)",
    "- duration_sec: $($TrajectoryReport.duration_sec)",
    "- path_length_m: $($TrajectoryReport.path_length_m)",
    "- net_displacement_m: $($TrajectoryReport.net_displacement_m)",
    "- mean_step_m: $($TrajectoryReport.mean_step_m)",
    "- max_step_m: $($TrajectoryReport.max_step_m)",
    "- mean_speed_mps: $($TrajectoryReport.mean_speed_mps)",
    '',
    '## Границы траектории',
    '',
    "- min_x: $($TrajectoryReport.bounding_box.min_x)",
    "- max_x: $($TrajectoryReport.bounding_box.max_x)",
    "- min_y: $($TrajectoryReport.bounding_box.min_y)",
    "- max_y: $($TrajectoryReport.bounding_box.max_y)",
    "- min_z: $($TrajectoryReport.bounding_box.min_z)",
    "- max_z: $($TrajectoryReport.bounding_box.max_z)",
    '',
    '## Начальная и конечная поза',
    '',
    "- start_pose: t=$($TrajectoryReport.start_pose.timestamp_sec) x=$($TrajectoryReport.start_pose.x) y=$($TrajectoryReport.start_pose.y) z=$($TrajectoryReport.start_pose.z)",
    "- end_pose: t=$($TrajectoryReport.end_pose.timestamp_sec) x=$($TrajectoryReport.end_pose.x) y=$($TrajectoryReport.end_pose.y) z=$($TrajectoryReport.end_pose.z)"
  )

  Set-Content -Path $SummaryPath -Value ($summaryLines -join "`r`n") -Encoding UTF8
}
