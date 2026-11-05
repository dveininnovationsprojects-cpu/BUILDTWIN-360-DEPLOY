#!/usr/bin/env bash
# Creates prod/.env.prod with new random secrets. Run once on the VM:
#   ./prod/gen-secrets.sh buildtwin.yourcompany.com
# Prints no secret values. Refuses to overwrite an existing .env.prod.
set -euo pipefail
DOMAIN="${1:?usage: gen-secrets.sh <domain>}"
OUT="$(cd "$(dirname "$0")" && pwd)/.env.prod"
[ -e "$OUT" ] && { echo "$OUT already exists; not overwriting" >&2; exit 1; }
rnd() { openssl rand -base64 "$1" | tr -d '/+=\n' | cut -c1-"$2"; }
umask 177
cat > "$OUT" <<EOF
DOMAIN=$DOMAIN
POSTGRES_DB=buildtwin
POSTGRES_USER=buildtwin
POSTGRES_PASSWORD=$(rnd 48 40)
JWT_SECRET_KEY=$(rnd 96 80)
APP_SEED_ADMIN_PASSWORD=$(rnd 32 24)
APP_SEED_ENABLED=false
EOF
chmod 600 "$OUT"
echo "Created $OUT (mode 600). Values were not printed."
echo "For the Jenkins credential buildtwin-prod-admin-password, read it with:"
echo "  grep '^APP_SEED_ADMIN_PASSWORD=' $OUT | cut -d= -f2-"
