#!/usr/bin/env bash
# Runs on the production VM (called by Jenkinsfile.prod over SSH).
# Usage: prod/deploy.sh <backend-ref> <frontend-ref>      (branch or tag names)
set -euo pipefail

BACKEND_REF="${1:?backend ref}"
FRONTEND_REF="${2:?frontend ref}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_REPO="https://github.com/dveininnovationsprojects-cpu/BUILDTWIN-360-BACKEND.git"
FRONTEND_REPO="https://github.com/dveininnovationsprojects-cpu/BUILDTWIN-360-FRONTEND.git"
cd "$ROOT"

[ -f prod/.env.prod ] || { echo "prod/.env.prod is missing"; exit 1; }
COMPOSE="docker compose --env-file prod/.env.prod -f prod/docker-compose.prod.yml"

checkout() {  # dir repo ref
  if [ -d "$1/.git" ]; then git -C "$1" fetch --tags --force origin; else git clone "$2" "$1"; fi
  git -C "$1" checkout --force "$3"
  git -C "$1" reset --hard "origin/$3" 2>/dev/null || true
  echo "$1 at $(git -C "$1" rev-parse --short HEAD)"
}
checkout backend "$BACKEND_REPO" "$BACKEND_REF"
checkout frontend "$FRONTEND_REPO" "$FRONTEND_REF"

# Dockerfiles and nginx files are copied in unless the app repo tracks its own
for pair in "backend Dockerfile docker/backend" "backend .dockerignore docker/backend" \
            "frontend Dockerfile docker/frontend" "frontend .dockerignore docker/frontend" \
            "frontend nginx.conf docker/frontend" "frontend security-headers.inc docker/frontend"; do
  set -- $pair
  git -C "$1" ls-files --error-unmatch "$2" >/dev/null 2>&1 || cp "$3/$2" "$1/$2"
done

# Restore point before anything changes
if $COMPOSE ps --status running postgres 2>/dev/null | grep -q postgres; then
  prod/backup-prod.sh
fi

$COMPOSE up -d --build --remove-orphans
$COMPOSE ps
echo "DEPLOY_OK backend=$(git -C backend rev-parse --short HEAD) frontend=$(git -C frontend rev-parse --short HEAD)"
