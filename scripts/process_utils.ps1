Set-StrictMode -Version Latest

function New-BackslashString {
  param([int]$Count)

  if ($Count -le 0) {
    return ''
  }

  return [string]::new([char]'\', $Count)
}

function ConvertTo-ProcessArgumentString {
  param([string[]]$ArgumentList)

  if (-not $ArgumentList -or $ArgumentList.Count -eq 0) {
    return ''
  }

  $encodedArguments = foreach ($argument in $ArgumentList) {
    if ($null -eq $argument -or $argument.Length -eq 0) {
      '""'
      continue
    }

    if ($argument -notmatch '[\s"]') {
      $argument
      continue
    }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $pendingBackslashes = 0

    foreach ($character in $argument.ToCharArray()) {
      if ($character -eq '\') {
        $pendingBackslashes++
        continue
      }

      if ($character -eq '"') {
        [void]$builder.Append((New-BackslashString -Count ($pendingBackslashes * 2 + 1)))
        [void]$builder.Append('"')
        $pendingBackslashes = 0
        continue
      }

      if ($pendingBackslashes -gt 0) {
        [void]$builder.Append((New-BackslashString -Count $pendingBackslashes))
        $pendingBackslashes = 0
      }

      [void]$builder.Append($character)
    }

    if ($pendingBackslashes -gt 0) {
      [void]$builder.Append((New-BackslashString -Count ($pendingBackslashes * 2)))
    }

    [void]$builder.Append('"')
    $builder.ToString()
  }

  return ($encodedArguments -join ' ')
}

function ConvertTo-ProcessOutputLines {
  param([string]$Text)

  if ([string]::IsNullOrEmpty($Text)) {
    return ,([string[]]@())
  }

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($line in ($Text -split "`r?`n")) {
    $lines.Add($line)
  }

  if ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') {
    $lines.RemoveAt($lines.Count - 1)
  }

  return ,([string[]]$lines.ToArray())
}

function Invoke-LoggedProcess {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$ArgumentList,
    [string]$WorkingDirectory = '',
    [int]$TimeoutSeconds = 0,
    [switch]$PrintOutput,
    [switch]$AllowNonZeroExit,
    [string]$FailureMessage = ''
  )

  # Start-Process без -Wait в Windows PowerShell 5.1 периодически возвращает пустой
  # ExitCode даже после WaitForExit(). Для orchestration-скриптов это даёт ложные
  # падения, поэтому используем System.Diagnostics.Process напрямую.
  $startInfo = New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName = $FilePath
  $startInfo.Arguments = ConvertTo-ProcessArgumentString -ArgumentList $ArgumentList
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
    $startInfo.WorkingDirectory = $WorkingDirectory
  }

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $startInfo

  $started = $false
  $timedOut = $false
  $exitCode = $null
  $stdoutText = ''
  $stderrText = ''

  try {
    $started = $process.Start()
    if (-not $started) {
      throw "Не удалось запустить процесс '$FilePath'."
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    if ($TimeoutSeconds -gt 0) {
      if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $timedOut = $true
        try {
          & taskkill /PID $process.Id /T /F | Out-Null
        }
        catch {
          if (-not $process.HasExited) {
            $process.Kill()
          }
        }
      }
    }

    if ($started) {
      $process.WaitForExit()
      $exitCode = $process.ExitCode
    }

    $stdoutText = $stdoutTask.GetAwaiter().GetResult()
    $stderrText = $stderrTask.GetAwaiter().GetResult()
  }
  finally {
    if ($process) {
      $process.Dispose()
    }
  }

  $stdoutLines = ConvertTo-ProcessOutputLines -Text $stdoutText
  $stderrLines = ConvertTo-ProcessOutputLines -Text $stderrText

  if ($PrintOutput) {
    foreach ($line in $stdoutLines) {
      Write-Host $line
    }
    foreach ($line in $stderrLines) {
      Write-Host $line
    }
  }

  $result = [pscustomobject]@{
    ExitCode = $exitCode
    TimedOut = $timedOut
    StdOutLines = $stdoutLines
    StdErrLines = $stderrLines
    CombinedLines = @($stdoutLines + $stderrLines)
  }

  if ($timedOut -and -not $AllowNonZeroExit) {
    if ([string]::IsNullOrWhiteSpace($FailureMessage)) {
      throw "Процесс '$FilePath' превысил timeout $TimeoutSeconds секунд."
    }
    throw "$FailureMessage Процесс превысил timeout $TimeoutSeconds секунд."
  }

  if (-not $AllowNonZeroExit -and $exitCode -ne 0) {
    if ([string]::IsNullOrWhiteSpace($FailureMessage)) {
      throw "Процесс '$FilePath' завершился с кодом $exitCode."
    }
    throw "$FailureMessage Код возврата: $exitCode."
  }

  return $result
}

function Invoke-RosEnvCommand {
  param(
    [Parameter(Mandatory = $true)]
    [string]$EnvScript,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments,
    [string]$WorkingDirectory = '',
    [int]$TimeoutSeconds = 0,
    [switch]$PrintOutput,
    [switch]$AllowNonZeroExit,
    [string]$FailureMessage = ''
  )

  return Invoke-LoggedProcess `
    -FilePath $EnvScript `
    -ArgumentList $Arguments `
    -WorkingDirectory $WorkingDirectory `
    -TimeoutSeconds $TimeoutSeconds `
    -PrintOutput:$PrintOutput `
    -AllowNonZeroExit:$AllowNonZeroExit `
    -FailureMessage $FailureMessage
}



