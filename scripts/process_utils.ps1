Set-StrictMode -Version Latest

function Invoke-LoggedProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList,
    [switch]$PrintOutput,
    [switch]$AllowNonZeroExit,
    [string]$FailureMessage = ''
  )

  $stdoutPath = Join-Path $env:TEMP ('yoga_cam_sub_process_' + [System.Guid]::NewGuid().ToString('N') + '.stdout.log')
  $stderrPath = Join-Path $env:TEMP ('yoga_cam_sub_process_' + [System.Guid]::NewGuid().ToString('N') + '.stderr.log')

  try {
    $process = Start-Process `
      -FilePath $FilePath `
      -ArgumentList $ArgumentList `
      -NoNewWindow `
      -Wait `
      -PassThru `
      -RedirectStandardOutput $stdoutPath `
      -RedirectStandardError $stderrPath

    $stdoutLines = if (Test-Path $stdoutPath) {
      @(Get-Content -Path $stdoutPath)
    } else {
      @()
    }
    $stderrLines = if (Test-Path $stderrPath) {
      @(Get-Content -Path $stderrPath)
    } else {
      @()
    }

    if ($PrintOutput) {
      foreach ($line in $stdoutLines) {
        Write-Host $line
      }
      foreach ($line in $stderrLines) {
        Write-Host $line
      }
    }

    $result = [pscustomobject]@{
      ExitCode = $process.ExitCode
      StdOutLines = $stdoutLines
      StdErrLines = $stderrLines
      CombinedLines = @($stdoutLines + $stderrLines)
    }

    if (-not $AllowNonZeroExit -and $process.ExitCode -ne 0) {
      if ([string]::IsNullOrWhiteSpace($FailureMessage)) {
        throw "Процесс '$FilePath' завершился с кодом $($process.ExitCode)."
      }
      throw "$FailureMessage Код возврата: $($process.ExitCode)."
    }

    return $result
  }
  finally {
    Remove-Item -Path $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
  }
}

function Invoke-RosEnvCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EnvScript,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [switch]$PrintOutput,
    [switch]$AllowNonZeroExit,
    [string]$FailureMessage = ''
  )

  return Invoke-LoggedProcess `
    -FilePath $EnvScript `
    -ArgumentList $Arguments `
    -PrintOutput:$PrintOutput `
    -AllowNonZeroExit:$AllowNonZeroExit `
    -FailureMessage $FailureMessage
}
