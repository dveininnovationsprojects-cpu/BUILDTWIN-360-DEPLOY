# Restores a backup made by backup.ps1.
# By default it restores into the LIVE database and needs -Force, because it replaces existing data.
# Use -TargetDb to restore into a different database (it is created if missing).
param(
    [Parameter(Mandatory = $true)][string]$File,
    [string]$Container = 'buildtwin-staging-postgres-1',
    [string]$TargetDb,
    [switch]$Force
)

function Invoke-Docker {
    param([string[]]$DockerArgs)
    $out = & docker @DockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "docker $($DockerArgs -join ' ') failed: $out" }
    return $out
}

if (-not (Test-Path $File)) { throw "Backup file not found: $File" }

$db   = (Invoke-Docker @('exec', $Container, 'printenv', 'POSTGRES_DB')   | Out-String).Trim()
$user = (Invoke-Docker @('exec', $Container, 'printenv', 'POSTGRES_USER') | Out-String).Trim()

if (-not $TargetDb) {
    $TargetDb = $db
    if (-not $Force) { throw "This replaces data in the live database '$db'. Re-run with -Force, or use -TargetDb to restore elsewhere." }
}

$inside = '/tmp/restore.dump'
Invoke-Docker @('cp', $File, "${Container}:$inside") | Out-Null

if ($TargetDb -ne $db) {
    $exists = (Invoke-Docker @('exec', $Container, 'psql', '-U', $user, '-d', 'postgres', '-tAc', "SELECT 1 FROM pg_database WHERE datname='$TargetDb'") | Out-String).Trim()
    if ($exists -ne '1') {
        Invoke-Docker @('exec', $Container, 'psql', '-U', $user, '-d', 'postgres', '-c', "CREATE DATABASE `"$TargetDb`"") | Out-Null
    }
}

# --clean --if-exists drops existing objects first so the restore is repeatable
Invoke-Docker @('exec', $Container, 'pg_restore', '-U', $user, '-d', $TargetDb, '--clean', '--if-exists', '--no-owner', $inside) | Out-Null
Invoke-Docker @('exec', $Container, 'rm', '-f', $inside) | Out-Null

Write-Output "RESTORE_OK $File -> database '$TargetDb'"
