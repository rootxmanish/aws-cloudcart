#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  CloudCart — App Tier Setup Script (Amazon Linux 2023)
#  Runs as EC2 User Data or manually: sudo bash setup-app.sh
#
#  What it does:
#    1. Installs Python 3.12
#    2. Pulls DB credentials and JWT secret from SSM Parameter Store
#    3. Creates /opt/cloudcart/backend/.env with real values
#    4. Syncs backend code from S3 (or uses pre-copied files)
#    5. Creates a Python venv and installs pinned dependencies
#    6. Installs and enables the cloudcart systemd service
#    7. Waits for /api/health to return 200 before exiting
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ── CONFIG ─────────────────────────────────────────────────────
APP_DIR="/opt/cloudcart"
BACKEND_DIR="$APP_DIR/backend"
VENV_DIR="$APP_DIR/venv"
SERVICE_NAME="cloudcart"
APP_PORT="8000"
APP_USER="ec2-user"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LOG_FILE="/var/log/cloudcart-app-setup.log"

# S3 bucket where backend code is stored (optional)
S3_BACKEND_BUCKET="${S3_BACKEND_BUCKET:-}"

exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] [INFO]  $*"; }
warn() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] [WARN]  $*"; }
err()  { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] [ERROR] $*" >&2; }

log "════════════════════════════════════════"
log "  CloudCart App Tier Setup"
log "  Region: $AWS_REGION"
log "════════════════════════════════════════"

# ── 1. SYSTEM UPDATE & PYTHON ──────────────────────────────────
log "Updating packages and installing Python 3.12…"
dnf update -y
dnf install -y python3.12 python3.12-pip

# ── 2. APP DIRECTORY ───────────────────────────────────────────
log "Creating app directory: $APP_DIR"
mkdir -p "$BACKEND_DIR"
chown -R "$APP_USER":"$APP_USER" "$APP_DIR"

# ── 3. PULL CODE FROM S3 (if configured) ──────────────────────
if [[ -n "$S3_BACKEND_BUCKET" ]]; then
  log "Syncing backend code from S3: $S3_BACKEND_BUCKET"
  aws s3 sync "s3://${S3_BACKEND_BUCKET}/backend/" "$BACKEND_DIR/" \
    --region "$AWS_REGION" \
    --delete
  chown -R "$APP_USER":"$APP_USER" "$BACKEND_DIR"
  log "Backend code synced from S3"
else
  log "No S3_BACKEND_BUCKET set — expecting code at $BACKEND_DIR"
fi

# ── 4. FETCH SECRETS FROM SSM ─────────────────────────────────
log "Fetching secrets from SSM Parameter Store…"

ssm_get() {
  aws ssm get-parameter \
    --name "$1" \
    --with-decryption \
    --query "Parameter.Value" \
    --output text \
    --region "$AWS_REGION" 2>/dev/null || echo ""
}

DB_HOST=$(ssm_get "/cloudcart/db-host")
DB_USER=$(ssm_get "/cloudcart/db-user")
DB_PASSWORD=$(ssm_get "/cloudcart/db-password")
DB_NAME=$(ssm_get "/cloudcart/db-name")
JWT_SECRET=$(ssm_get "/cloudcart/jwt-secret")

# Validate required secrets
MISSING=()
[[ -z "$DB_HOST"     ]] && MISSING+=("/cloudcart/db-host")
[[ -z "$DB_PASSWORD" ]] && MISSING+=("/cloudcart/db-password")
[[ -z "$JWT_SECRET"  ]] && MISSING+=("/cloudcart/jwt-secret")

if [[ ${#MISSING[@]} -gt 0 ]]; then
  err "Missing required SSM parameters: ${MISSING[*]}"
  err "Create them in SSM Parameter Store (SecureString) before running this script."
  exit 1
fi

log "All required SSM parameters found ✅"

# ── 5. WRITE .ENV FILE ─────────────────────────────────────────
log "Writing $BACKEND_DIR/.env"
cat > "$BACKEND_DIR/.env" << ENVFILE
DB_USER=${DB_USER:-cloudcart}
DB_PASSWORD=${DB_PASSWORD}
DB_HOST=${DB_HOST}
DB_PORT=3306
DB_NAME=${DB_NAME:-cloudcart}
JWT_SECRET=${JWT_SECRET}
JWT_EXPIRATION_MINUTES=60
ENVFILE

# Restrict permissions — only ec2-user can read
chown "$APP_USER":"$APP_USER" "$BACKEND_DIR/.env"
chmod 600 "$BACKEND_DIR/.env"
log ".env written with restricted permissions (600)"

# ── 6. PYTHON VENV & DEPENDENCIES ─────────────────────────────
log "Creating Python virtual environment…"
sudo -u "$APP_USER" python3.12 -m venv "$VENV_DIR"

log "Installing dependencies from requirements.txt…"
if [[ -f "$BACKEND_DIR/requirements.txt" ]]; then
  sudo -u "$APP_USER" "$VENV_DIR/bin/pip" install \
    --upgrade pip \
    --quiet \
    -r "$BACKEND_DIR/requirements.txt"
  log "Dependencies installed ✅"
else
  err "requirements.txt not found at $BACKEND_DIR/requirements.txt"
  err "Ensure backend code is present before running this script."
  exit 1
fi

# ── 7. SYSTEMD SERVICE ─────────────────────────────────────────
log "Installing systemd service: $SERVICE_NAME"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" << SYSTEMD
[Unit]
Description=CloudCart FastAPI Application
Documentation=https://github.com/your-org/cloudcart
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${APP_USER}
Group=${APP_USER}
WorkingDirectory=${BACKEND_DIR}
EnvironmentFile=${BACKEND_DIR}/.env
ExecStart=${VENV_DIR}/bin/uvicorn app.main:app --host 0.0.0.0 --port ${APP_PORT} --workers 2
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cloudcart

# Security hardening
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/tmp
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
SYSTEMD

# ── 8. ENABLE & START SERVICE ─────────────────────────────────
log "Enabling and starting $SERVICE_NAME service…"
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

# ── 9. HEALTH CHECK WAIT LOOP ─────────────────────────────────
log "Waiting for app to respond on port $APP_PORT…"
for i in {1..12}; do
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://localhost:${APP_PORT}/api/health" 2>/dev/null || echo "000")

  if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "503" ]]; then
    # 503 means app started but DB not connected yet — still a sign the app is up
    log "✅ App server is UP — HTTP $HTTP_STATUS (attempt $i)"
    break
  fi

  warn "App not ready yet — HTTP $HTTP_STATUS (attempt $i/12) — sleeping 5s…"
  sleep 5
done

# Final check — must be 200
FINAL_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  "http://localhost:${APP_PORT}/api/health" 2>/dev/null || echo "000")

if [[ "$FINAL_STATUS" != "200" ]]; then
  err "❌ App did not reach healthy state (HTTP $FINAL_STATUS)"
  err "Check logs: journalctl -u $SERVICE_NAME -n 50"
  exit 1
fi

log "════════════════════════════════════════"
log "  App Tier Setup Complete ✅"
log "  Listening on port $APP_PORT"
log "  Service: $SERVICE_NAME"
log "  Logs: journalctl -u $SERVICE_NAME -f"
log "════════════════════════════════════════"
