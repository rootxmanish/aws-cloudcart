#!/bin/bash
# ═══════════════════════════════════════════════════════════════
#  CloudCart — Web Tier Setup Script (Amazon Linux 2023)
#  Runs as EC2 User Data or manually: sudo bash setup-web.sh
#
#  What it does:
#    1. Installs Nginx
#    2. Fetches the Internal ALB DNS from SSM Parameter Store
#    3. Writes the Nginx config with the real ALB DNS substituted
#    4. Deploys frontend files from S3 (or local copy)
#    5. Enables & starts Nginx
#    6. Waits for a successful health check before exiting
# ═══════════════════════════════════════════════════════════════
set -euo pipefail

# ── CONFIG ─────────────────────────────────────────────────────
WEB_ROOT="/var/www/cloudcart/frontend"
NGINX_CONF="/etc/nginx/conf.d/cloudcart.conf"
AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
LOG_FILE="/var/log/cloudcart-web-setup.log"

# S3 bucket where frontend files are stored (optional — set or leave blank)
# If blank, the script expects files to already be at $WEB_ROOT.
S3_FRONTEND_BUCKET="${S3_FRONTEND_BUCKET:-}"

exec > >(tee -a "$LOG_FILE") 2>&1

log()  { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] [INFO]  $*"; }
warn() { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] [WARN]  $*"; }
err()  { echo "[$(date '+%Y-%m-%dT%H:%M:%S%z')] [ERROR] $*" >&2; }

log "════════════════════════════════════════"
log "  CloudCart Web Tier Setup"
log "  Region: $AWS_REGION"
log "════════════════════════════════════════"

# ── 1. SYSTEM UPDATE & NGINX ───────────────────────────────────
log "Updating packages and installing Nginx…"
dnf update -y
dnf install -y nginx

# ── 2. FETCH INTERNAL ALB DNS FROM SSM ────────────────────────
log "Fetching Internal ALB DNS from SSM Parameter Store…"
INTERNAL_ALB_DNS=$(aws ssm get-parameter \
  --name "/cloudcart/internal-alb-dns" \
  --query "Parameter.Value" \
  --output text \
  --region "$AWS_REGION" 2>/dev/null || echo "")

if [[ -z "$INTERNAL_ALB_DNS" ]]; then
  warn "SSM param /cloudcart/internal-alb-dns not found."
  warn "Nginx will be configured with a placeholder — update manually."
  INTERNAL_ALB_DNS="REPLACE_WITH_INTERNAL_ALB_DNS"
fi

log "Internal ALB DNS: $INTERNAL_ALB_DNS"

# ── 3. WEB ROOT ────────────────────────────────────────────────
log "Creating web root: $WEB_ROOT"
mkdir -p "$WEB_ROOT"
chown -R nginx:nginx /var/www/cloudcart

# ── 4. DEPLOY FRONTEND FILES ───────────────────────────────────
if [[ -n "$S3_FRONTEND_BUCKET" ]]; then
  log "Syncing frontend files from S3: $S3_FRONTEND_BUCKET"
  aws s3 sync "s3://${S3_FRONTEND_BUCKET}/frontend/" "$WEB_ROOT/" \
    --region "$AWS_REGION" \
    --delete
  chown -R nginx:nginx "$WEB_ROOT"
  log "Frontend files synced from S3"
else
  log "No S3_FRONTEND_BUCKET set — skipping S3 sync."
  log "Deploy frontend files manually to $WEB_ROOT"
fi

# ── 5. NGINX SITE CONFIG ───────────────────────────────────────
log "Writing Nginx config: $NGINX_CONF"

# Disable default config
[ -f /etc/nginx/conf.d/default.conf ] && \
  mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.conf.bak

cat > "$NGINX_CONF" << NGINXCONF
# CloudCart — Nginx Web Tier Config
# Internal ALB DNS: ${INTERNAL_ALB_DNS}

# Rate limiting: 20 req/s per IP
limit_req_zone \$binary_remote_addr zone=cloudcart_limit:10m rate=20r/s;

server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    root ${WEB_ROOT};
    index index.html;

    # Security headers
    add_header X-Content-Type-Options  "nosniff" always;
    add_header X-Frame-Options         "SAMEORIGIN" always;
    add_header X-XSS-Protection        "1; mode=block" always;
    add_header Referrer-Policy         "strict-origin-when-cross-origin" always;
    server_tokens off;

    # Gzip
    gzip on;
    gzip_vary on;
    gzip_types text/plain text/css application/javascript application/json image/svg+xml;
    gzip_min_length 1024;

    # Static files
    location / {
        try_files \$uri \$uri/ /index.html;
        expires 1h;
        add_header Cache-Control "public, max-age=3600";
    }

    # CSS / JS — longer cache
    location ~* \.(css|js)\$ {
        expires 7d;
        add_header Cache-Control "public, max-age=604800, immutable";
    }

    # Proxy /api/* → Internal ALB (App Tier)
    location /api/ {
        limit_req zone=cloudcart_limit burst=40 nodelay;

        proxy_pass         http://${INTERNAL_ALB_DNS};
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_set_header   Connection        "";

        proxy_connect_timeout 5s;
        proxy_read_timeout    15s;
    }

    # ALB health check endpoint
    location /health {
        access_log off;
        return 200 "ok\n";
        add_header Content-Type text/plain;
    }

    access_log /var/log/nginx/cloudcart-access.log combined;
    error_log  /var/log/nginx/cloudcart-error.log warn;
}
NGINXCONF

# ── 6. VALIDATE & START NGINX ─────────────────────────────────
log "Validating Nginx config…"
nginx -t

log "Enabling and starting Nginx…"
systemctl enable nginx
systemctl start nginx

# ── 7. LOG ROTATION ───────────────────────────────────────────
cat > /etc/logrotate.d/cloudcart-nginx << 'LOGROTATE'
/var/log/nginx/cloudcart-*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        nginx -s reopen > /dev/null 2>&1 || true
    endscript
}
LOGROTATE

# ── 8. HEALTH CHECK WAIT LOOP ─────────────────────────────────
log "Waiting for Nginx to respond on port 80…"
for i in {1..10}; do
  if curl -sf "http://localhost/health" > /dev/null 2>&1; then
    log "✅ Nginx is UP (attempt $i)"
    break
  fi
  warn "Not ready yet (attempt $i/10) — sleeping 5s…"
  sleep 5
done

if ! curl -sf "http://localhost/health" > /dev/null 2>&1; then
  err "❌ Nginx did not start — check /var/log/nginx/error.log"
  exit 1
fi

log "════════════════════════════════════════"
log "  Web Tier Setup Complete ✅"
log "  Root: $WEB_ROOT"
log "  API proxy → $INTERNAL_ALB_DNS"
log "  Logs: /var/log/nginx/cloudcart-*.log"
log "════════════════════════════════════════"
