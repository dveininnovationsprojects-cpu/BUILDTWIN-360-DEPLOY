# Creates a compressed PostgreSQL backup (pg_dump custom format) of the BuildTwin database.
# Works with Windows PowerShell 5.1 and PowerShell 7. Prints BACKUP_OK <path> on success.
param(
    [string]$Container = 'buildtwin-staging-postgres-1',
    [string]$BackupDir = (Join-Path $PSScriptRoot '..\backups'),
    [int]$KeepDays = 7
)

function Invoke-Docker {
    param([string[]]$DockerArgs)
    $out = & docker @DockerArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "docker $($DockerArgs -join ' ') failed: $out" }
    return $out
}

New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null

$db   = (Invoke-Docker @('exec', $Container, 'printenv', 'POSTGRES_DB')   | Out-String).Trim()
$user = (Invoke-Docker @('exec', $Container, 'printenv', 'POSTGRES_USER') | Out-String).Trim()

$name   = 'buildtwin-{0}.dump' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$inside = "/tmp/$name"
$target = Join-Path $BackupDir $name

Invoke-Docker @('exec', $Container, 'pg_dump', '-U', $user, '-d', $db, '-Fc', '-f', $inside) | Out-Null

# The archive must be readable and contain objects, otherwise the backup is useless
$entries = (Invoke-Docker @('exec', $Container, 'pg_restore', '-l', $inside) | Out-String)
if (($entries -split "`n" | Where-Object { $_ -match '^\d+;' }).Count -eq 0) {
    throw 'Backup archive has no entries'
}

Invoke-Docker @('cp', "${Container}:$inside", $target) | Out-Null
Invoke-Docker @('exec', $Container, 'rm', '-f', $inside) | Out-Null

if (-not (Test-Path $target) -or (Get-Item $target).Length -eq 0) { throw "Backup file missing or empty: $target" }

# Retention: delete dumps older than $KeepDays days
Get-ChildItem -Path $BackupDir -Filter 'buildtwin-*.dump' |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepDays) } |
    Remove-Item -Force

Write-Output ("BACKUP_OK {0} ({1:N0} bytes)" -f $target, (Get-Item $target).Length)
