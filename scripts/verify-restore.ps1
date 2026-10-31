# Proves a backup is restorable: restores it into a throw-away database and compares the table list and
# row counts with the live database, then drops the throw-away database and writes a verification record.
# Fails (non-zero exit) if the restore errors or the table lists differ. Row-count differences are reported
# as warnings because the live database may change between the backup and the check.
param(
    [string]$File,
    [string]$Container = 'buildtwin-staging-postgres-1',
    [string]$BackupDir = (Join-Path $PSScriptRoot '..\backups')
)

function Invoke-Docker {
    param([string[]]$DockerArgs)
    $out = & docker @DockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "docker $($DockerArgs -join ' ') failed: $out" }
    return $out
}

if (-not $File) {
    $latest = Get-ChildItem -Path $BackupDir -Filter 'buildtwin-*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $latest) { throw "No backups found in $BackupDir" }
    $File = $latest.FullName
}

$db   = (Invoke-Docker @('exec', $Container, 'printenv', 'POSTGRES_DB')   | Out-String).Trim()
$user = (Invoke-Docker @('exec', $Container, 'printenv', 'POSTGRES_USER') | Out-String).Trim()
$temp = 'restore_verify_{0}' -f (Get-Date -Format 'yyyyMMddHHmmss')

# Exact row count per table (information_schema + query_to_xml avoids hand-written SQL per table)
$countSql = "SELECT table_name || '=' || (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' ORDER BY table_name"

function Get-Counts([string]$Database) {
    $raw = Invoke-Docker @('exec', $Container, 'psql', '-U', $user, '-d', $Database, '-tA', '-c', $countSql) | Out-String
    $map = [ordered]@{}
    foreach ($line in ($raw -split "`n")) {
        $line = $line.Trim()
        if ($line -match '^(.+)=(\d+)$') { $map[$Matches[1]] = [int]$Matches[2] }
    }
    return $map
}

$problems = @()
$warnings = @()
$restored = $null
try {
    & (Join-Path $PSScriptRoot 'restore.ps1') -File $File -Container $Container -TargetDb $temp | Out-Null

    $source   = Get-Counts $db
    $restored = Get-Counts $temp

    $missing = $source.Keys   | Where-Object { -not $restored.Contains($_) }
    $extra   = $restored.Keys | Where-Object { -not $source.Contains($_) }
    if ($missing) { $problems += "Tables missing after restore: $($missing -join ', ')" }
    if ($extra)   { $problems += "Unexpected tables after restore: $($extra -join ', ')" }

    foreach ($t in $source.Keys) {
        if ($restored.Contains($t) -and $restored[$t] -ne $source[$t]) {
            $warnings += "Row count differs for ${t}: live=$($source[$t]) restored=$($restored[$t])"
        }
    }
    if ($source.Count -eq 0) { $problems += 'Live database has no tables to compare' }
}
catch {
    $problems += $_.Exception.Message
}
finally {
    try {
        Invoke-Docker @('exec', $Container, 'psql', '-U', $user, '-d', 'postgres', '-c', "DROP DATABASE IF EXISTS `"$temp`"") | Out-Null
    } catch { $warnings += "Could not drop temporary database ${temp}: $($_.Exception.Message)" }
}

$status = if ($problems.Count -eq 0) { 'PASSED' } else { 'FAILED' }
$lines = @(
    'BuildTwin 360 - backup restore verification',
    "Result       : $status",
    "Date         : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    "Backup file  : $File",
    ('Backup size  : {0:N0} bytes' -f (Get-Item $File).Length),
    "Container    : $Container",
    "Live DB      : $db",
    "Temp DB      : $temp (dropped)",
    "Tables       : live=$(if ($source) { $source.Count } else { 0 }) restored=$(if ($restored) { $restored.Count } else { 0 })",
    ('Rows         : live={0} restored={1}' -f (($source.Values | Measure-Object -Sum).Sum), (($restored.Values | Measure-Object -Sum).Sum))
)
if ($warnings) { $lines += 'Warnings:'; $lines += ($warnings | ForEach-Object { "  - $_" }) }
if ($problems) { $lines += 'Problems:'; $lines += ($problems | ForEach-Object { "  - $_" }) }

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
$record = Join-Path $BackupDir ('restore-verification-{0}.txt' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$lines | Set-Content -Path $record -Encoding UTF8
$lines | ForEach-Object { Write-Output $_ }
Write-Output "Record saved : $record"

if ($problems.Count -gt 0) { exit 1 }
