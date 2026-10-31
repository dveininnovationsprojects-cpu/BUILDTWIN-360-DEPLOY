# BuildTwin 360 - Backup and Restore Procedure

Covers the staging PostgreSQL database (container `buildtwin-staging-postgres-1`, database `buildtwin`).
Required by the specification: daily backup in a production-like environment and at least one documented
restore test before the final release.

## What runs

| Item | Detail |
|---|---|
| Schedule | Nightly around 02:00 by the Jenkins job that uses `Jenkinsfile.backup` |
| Method | `pg_dump` custom format (`-Fc`), compressed, taken inside the PostgreSQL container |
| Location | `C:\BuildTwinBackups` on the Jenkins host (outside any workspace) |
| Retention | 7 days; older dumps are deleted by the backup script |
| Verification | After every backup the latest dump is restored into a temporary database and compared with the live one |

## Set up the Jenkins job

1. New Item -> `buildtwin360-staging-backup` -> Pipeline.
2. Pipeline script from SCM -> Git -> `https://github.com/dveininnovationsprojects-cpu/BUILDTWIN-360-DEPLOY.git`, branch `*/main`.
3. Script Path: `Jenkinsfile.backup`. Save. The nightly trigger is defined in the file.
4. Run it once with Build Now and confirm the verification result is PASSED.

## Manual backup

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\backup.ps1 -BackupDir C:\BuildTwinBackups
```

## Restore

Restore into a separate database first to inspect the data:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\restore.ps1 -File C:\BuildTwinBackups\buildtwin-YYYYMMDD-HHMMSS.dump -TargetDb buildtwin_inspect
```

Restore over the live database (replaces its data, so `-Force` is required). Stop the backend first so
nothing writes during the restore:

```powershell
docker stop buildtwin-staging-backend-1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\restore.ps1 -File C:\BuildTwinBackups\buildtwin-YYYYMMDD-HHMMSS.dump -Force
docker start buildtwin-staging-backend-1
```

## Verify a backup is restorable

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\verify-restore.ps1 -BackupDir C:\BuildTwinBackups
```

The script restores the newest dump into a temporary database, compares table names and row counts with
the live database, drops the temporary database and writes `restore-verification-<timestamp>.txt`.
It exits non-zero if the restore fails or the table lists differ.

## Restore test record

| Field | Value |
|---|---|
| Date | 2026-10-31 14:14 |
| Environment | Staging, deployed by Jenkins (`buildtwin-staging-postgres-1`) |
| Backup file | `buildtwin-20261031-141413.dump` (about 166 KB, produced in a few seconds) |
| Restored into | Temporary database `restore_verify_20261031141415` (dropped afterwards) |
| Tables | 52 live, 52 restored |
| Rows | 105 live, 105 restored |
| Result | **PASSED** |
| Live-restore guard | Running `restore.ps1` without `-Force` against the live database is refused, as intended |

The staging database currently holds only seed data, so repeat this test on the final release candidate and
record the new result here before sign-off.

## Limits to be aware of

- Backups live on the same machine as the database. Copy `C:\BuildTwinBackups` to separate storage
  (another disk, network share or cloud bucket) to survive a host failure.
- The check covers schema and row counts, not application-level correctness of the data.
