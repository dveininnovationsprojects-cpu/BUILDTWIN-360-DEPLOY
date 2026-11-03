# BuildTwin 360 - production runbook (Linux VM)

Status: **prepared, not executed.** No production VM exists yet. This runbook, the `prod/` folder and
`Jenkinsfile.prod` cover the items listed as "Not performed" in the Deployment Execution Record.
Each step says who does it.

## Go-live blockers (close first)
- KTI-01: secrets removed from the backend repository and rotated.
- KTI-02: the 10 seeded users have default passwords. Production must not start with `APP_SEED_ENABLED=true` until this is fixed.
- KTI-03: vulnerable backend libraries. KTI-04: the 8 PostgreSQL 500 errors.
- KTI-05: versioned database migrations (the schema is currently changed by the app at startup).
- A version tag on each app repo (production deploys tags, not `main2`).

## 1. Infrastructure (you / cloud account)
- Linux VM (Ubuntu 22.04 or later), at least 2 vCPU, 4 GB RAM, 40 GB disk. Size up for production data volumes.
- Firewall: allow 22 (your IP only), 80 and 443. Nothing else, so PostgreSQL (5432) and the backend (8080) stay private.
- DNS: an A record for the production domain pointing to the VM. TLS certificates are then issued automatically by Caddy.
- Install Docker Engine and the Compose plugin. Create a `deploy` user in the `docker` group with an SSH key.
- Object storage: the application currently stores document links only (no storage service is configured). Decide the
  storage service with the developers before launch and record it here.

## 2. Secrets (you)
- On the VM: `git clone https://github.com/dveininnovationsprojects-cpu/BUILDTWIN-360-DEPLOY.git /opt/buildtwin`.
- `cp prod/.env.prod.example prod/.env.prod`, fill in the values and run `chmod 600 prod/.env.prod`.
  Use new random values: a 64+ character JWT key, a strong database password and a strong admin password.
- In Jenkins add: `buildtwin-prod-ssh` (SSH private key of the deploy user), `buildtwin-prod-domain` (secret text) and
  `buildtwin-prod-admin-password` (secret text, same as `APP_SEED_ADMIN_PASSWORD`).

## 3. Deploy (Jenkins job from `Jenkinsfile.prod`)
- Run the job with `BACKEND_REF`, `FRONTEND_REF` (tags) and `PROD_HOST`. A person must approve at the Approval stage.
- The VM takes a backup, builds the images and starts the stack. The pipeline then runs the smoke and Newman tests over HTTPS.
- First start on an empty database: set `APP_SEED_ENABLED=true` for that start only, then set it back to `false`.

## 4. Production smoke test and verification
- Pipeline: the site returns 200 over HTTPS, `/api/v1/projects` returns 401 without a token, backend port 8080 is not reachable, Newman passes.
- Manually: log in as the administrator and open the projects page, check the certificate in a browser and check the response headers.

## 5. Backup (VM)
- Cron for the `deploy` user: `0 2 * * * /opt/buildtwin/prod/backup-prod.sh >> /var/log/buildtwin-backup.log 2>&1`.
- Set `OFFSITE_CMD` (for example `aws s3 cp "$FILE" s3://company-bucket/buildtwin/`) so each dump leaves the VM.
- Once a month restore the latest dump into a temporary database and compare table and row counts, as on staging.

## 6. Monitoring (minimum)
- External uptime check on `https://<domain>/` (for example UptimeRobot or the cloud provider's check) with email alerts.
- Container logs are rotated (10 MB x 5). Read them with `docker compose --env-file prod/.env.prod -f prod/docker-compose.prod.yml logs --tail 200`.
- Use `docker stats --no-stream` and `df -h` for CPU, memory and disk. Alert when disk use is above 80%.
- Add a health endpoint check once Actuator is in the backend (KTI-06).

## 7. Rollback
- Application: run the Jenkins job again with the previous tags.
- Database: `prod/backup-prod.sh` runs before every deploy. To return data, stop the backend, restore that dump with
  `pg_restore --clean --if-exists` and start the backend. See `docs/BACKUP_RESTORE.md`.

## 8. Sign-off
- Record the Jenkins build number, start and end time, tags deployed, smoke results and the name of the approver.
  Then update the Deployment Execution Record, the Completed Deployment Checklist and the Release Verification Evidence.
