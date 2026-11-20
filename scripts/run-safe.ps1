param(
  [Parameter(Mandatory = $true)]
  [string[]]$BunArgs,
  [double]$MaxSeconds = 8,
  [double]$MaxMemoryMB = 1536
)

$ErrorActionPreference = 'Stop'

function Format-WinArg([string]$arg) {
  if ($arg -eq '') { return '""' }
  if ($arg -notmatch '[\s"]') { return $arg }
  $escaped = $arg -replace '(\\*)"', '$1$1\"'
  $escaped = $escaped -replace '(\\+)$', '$1$1'
  return '"' + $escaped + '"'
}

$argLine = ($BunArgs | ForEach-Object { Format-WinArg $_ }) -join ' '

$runId = [guid]::NewGuid().ToString('N').Substring(0, 8)
$tempDir = [System.IO.Path]::GetTempPath()
$stdoutPath = Join-Path $tempDir "bun-repro-stdout-$runId.log"
$stderrPath = Join-Path $tempDir "bun-repro-stderr-$runId.log"
$workDir = (Get-Location).Path

$existingPids = @(
  Get-Process -Name bun -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Id
)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath bun -ArgumentList $argLine -WorkingDirectory $workDir -PassThru -NoNewWindow -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

$killedReason = 'NONE'
$peakPrivateBytes = [int64]0
$peakWorkingSetBytes = [int64]0
$maxPidCount = 0
$seenNewPids = [System.Collections.Generic.HashSet[int]]::new()
[void]$seenNewPids.Add($proc.Id)
$samples = [System.Collections.Generic.List[string]]::new()
$inv = [System.Globalization.CultureInfo]::InvariantCulture
$nextSampleSec = 0.0

try {
  while ($true) {
    $newProcs = @(
      Get-Process -Name bun -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -notin $existingPids }
    )

    foreach ($np in $newProcs) {
      [void]$seenNewPids.Add($np.Id)
    }

    if ($newProcs.Count -gt $maxPidCount) {
      $maxPidCount = $newProcs.Count
    }

    $sumPriv = [int64]0
    $sumWs = [int64]0
    foreach ($np in $newProcs) {
      $sumPriv += [int64]$np.PrivateMemorySize64
      $sumWs += [int64]$np.WorkingSet64
    }
    if ($sumPriv -gt $peakPrivateBytes) { $peakPrivateBytes = $sumPriv }
    if ($sumWs -gt $peakWorkingSetBytes) { $peakWorkingSetBytes = $sumWs }

    $elapsed = $sw.Elapsed.TotalSeconds
    if ($newProcs.Count -gt 0 -and $elapsed -ge $nextSampleSec) {
      $samples.Add(("t={0}s procs={1} priv={2}MB ws={3}MB" -f $elapsed.ToString('F2', $inv), $newProcs.Count, ($sumPriv / 1MB).ToString('F1', $inv), ($sumWs / 1MB).ToString('F1', $inv)))
      $nextSampleSec = $elapsed + 0.5
    }

    if ($elapsed -ge $MaxSeconds) {
      $killedReason = 'TIMEOUT_GUARD'
      break
    }

    if ($peakPrivateBytes -ge ([int64]($MaxMemoryMB * 1MB))) {
      $killedReason = 'MEMORY_GUARD'
      break
    }

    if ($proc.HasExited -and $newProcs.Count -eq 0) {
      break
    }

    Start-Sleep -Milliseconds 250
  }
}
finally {
  if ($killedReason -ne 'NONE') {
    $allToKill = @(
      Get-Process -Name bun -ErrorAction SilentlyContinue |
        Where-Object { $_.Id -notin $existingPids } |
        Select-Object -ExpandProperty Id
    )
    foreach ($kid in $seenNewPids) {
      if ($kid -notin $allToKill) { $allToKill += $kid }
    }
    foreach ($kid in $allToKill) {
      Stop-Process -Id $kid -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Milliseconds 300
  }
  $sw.Stop()
}

$exitCode = if ($proc.HasExited) { $proc.ExitCode } else { -1 }

$leftover = @(
  Get-Process -Name bun -ErrorAction SilentlyContinue |
    Where-Object { $_.Id -notin $existingPids } |
    Select-Object -ExpandProperty Id
)

$stdoutText = if (Test-Path $stdoutPath) { Get-Content -Raw $stdoutPath -ErrorAction SilentlyContinue } else { '' }
$stderrText = if (Test-Path $stderrPath) { Get-Content -Raw $stderrPath -ErrorAction SilentlyContinue } else { '' }

Remove-Item -Path $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue

Write-Output "COMMAND: bun $argLine"
Write-Output "EXIT_CODE: $exitCode"
Write-Output ("ELAPSED_SEC: " + $sw.Elapsed.TotalSeconds.ToString('F3', $inv))
Write-Output "KILLED_REASON: $killedReason"
Write-Output ("PEAK_PRIVATE_MB: " + ($peakPrivateBytes / 1MB).ToString('F2', $inv))
Write-Output ("PEAK_WORKINGSET_MB: " + ($peakWorkingSetBytes / 1MB).ToString('F2', $inv))
Write-Output "MAX_CONCURRENT_BUN_PROCS: $maxPidCount"
Write-Output "LEFTOVER_NEW_BUN_PIDS: $($leftover.Count)"
Write-Output "SAMPLES: $($samples -join ' | ')"
Write-Output "--- STDOUT ---"
if ($stdoutText) { Write-Output $stdoutText.TrimEnd() } else { Write-Output "<empty>" }
Write-Output "--- STDERR ---"
if ($stderrText) { Write-Output $stderrText.TrimEnd() } else { Write-Output "<empty>" }
