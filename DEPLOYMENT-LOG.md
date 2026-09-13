# CloudCart — Deployment Log
# Deployed by: Manish
# Date: September 13, 2026
# Region: ap-south-1 (Mumbai)
# Architecture: AWS 3-Tier (Web → App → RDS MySQL)

---

## Overview

This file documents every command I ran manually to deploy the CloudCart
3-tier e-commerce application on AWS from scratch.

```
Internet
    ↓
Public ALB (cloudcart-public-alb)
    ↓
Web EC2 × 2  —  Nginx  (ap-south-1b + ap-south-1c)
    ↓
Internal ALB (cloudcart-internal-alb)
    ↓
App EC2 × 2  —  FastAPI / Uvicorn  (ap-south-1b + ap-south-1c)
    ↓
RDS MySQL 8.0  (private subnet, ap-south-1b)
```

---

## ═══════════════════════════════════════════════
## PART 1 — APP EC2 SETUP
## Instance: APP-Server-1 (ip-192-168-141-215)
## Private IP: 192.168.141.215 | Type: t2.micro
## ═══════════════════════════════════════════════

### Step 1 — Check who is logged in
```bash
whoami
# Output: root
```
> Verified I'm running as root on the App EC2 instance.

---

### Step 2 — Update system packages
```bash
dnf update -y
```
> Updated all system packages to latest versions on Amazon Linux 2023.

---

### Step 3 — Install required tools
```bash
dnf install -y python3 python3-pip git awscli mariadb105
```
> Installed:
> - python3 — Python runtime
> - python3-pip — Python package manager
> - git — version control
> - awscli — AWS CLI to pull code from S3
> - mariadb105 — MySQL client to connect to RDS

---

### Step 4 — Verify installations
```bash
python3 --version
pip3 --version
aws --version
mysql --version
```
> Confirmed all tools installed correctly before proceeding.

---

### Step 5 — Create application directories
```bash
mkdir -p /opt/cloudcart/backend
mkdir -p /opt/cloudcart/logs
chown -R ec2-user:ec2-user /opt/cloudcart
```
> Created the app directory at /opt/cloudcart and set ec2-user as owner.

---

### Step 6 — Pull backend code from S3
```bash
aws s3 ls s3://3-tier-project-10-09-2026/cloudcart/backend/
```
> Listed S3 bucket contents to verify files are there before syncing.

```bash
aws s3 sync s3://3-tier-project-10-09-2026/cloudcart/backend/ /opt/cloudcart/backend/
```
> Synced the entire backend folder from S3 to the App EC2 instance.
> This pulled: app/, requirements.txt, .env.example, nginx config, systemd service file.

```bash
ls -R /opt/cloudcart/backend
```
> Verified all files were downloaded correctly.

---

### Step 7 — Create Python virtual environment (first attempt with python3)
```bash
python3 -m venv /opt/cloudcart/venv
source /opt/cloudcart/venv/bin/activate
```
> Created isolated Python environment for the app dependencies.

---

### Step 8 — Test if app was running (it wasn't yet)
```bash
curl http://127.0.0.1:8000/health
ps
ss -t
curl http://127.0.0.1:8000/health
who
curl -I http://127.0.0.1:8000/docs
curl http://127.0.0.1:8000/
curl http://127.0.0.1:8000/api/health
```
> App was not running yet — confirmed no process on port 8000.

---

### Step 9 — Install Python dependencies
```bash
source /opt/cloudcart/venv/bin/activate
pip install --upgrade pip
pip install -r /opt/cloudcart/backend/requirements.txt
```
> Upgraded pip and installed all FastAPI dependencies (fastapi, uvicorn,
> sqlalchemy, PyMySQL, pydantic, pwdlib, PyJWT, etc.)

---

### Step 10 — Create and configure the .env file
```bash
vim /opt/cloudcart/backend/.env
```
> Created the environment file with RDS connection details:
> - DB_USER — RDS master username
> - DB_PASSWORD — RDS master password
> - DB_HOST — RDS endpoint URL
> - DB_PORT=3306
> - DB_NAME=cloudcart
> - JWT_SECRET — long random secret for JWT tokens

```bash
cat .env
# Verified contents (passwords hidden)
```

---

### Step 11 — Load env vars and test RDS connectivity
```bash
set -a
source /opt/cloudcart/backend/.env
set +a
```
> Exported all .env variables into the current shell session.

```bash
echo "$DB_HOST"
echo "$DB_USER"
echo "$DB_NAME"
```
> Confirmed the variables were loaded correctly.

```bash
timeout 5 bash -c "</dev/tcp/$DB_HOST/3306" && echo "PORT 3306 OPEN" || echo "PORT 3306 NOT REACHABLE"
```
> Tested TCP connectivity to RDS on port 3306.
> Output: PORT 3306 OPEN — confirmed security group rules working correctly.

---

### Step 12 — Connect to RDS and run schema
```bash
mysql -h "$DB_HOST" -u "$DB_USER" -p "$DB_NAME"
```
> Connected to RDS MySQL from App EC2 (only possible because App-SG
> allows port 3306 to Database-SG — web and internet cannot reach RDS directly).

```bash
aws s3 cp s3://3-tier-project-10-09-2026/cloudcart/database/schema.sql /tmp/schema.sql
ls -lh /tmp/schema.sql
mysql -h "$DB_HOST" -u "$DB_USER" -p "$DB_NAME" < /tmp/schema.sql
```
> Downloaded schema.sql from S3 and ran it against RDS.
> This created the 4 tables: users, products, orders, order_items
> and seeded sample product data.

---

### Step 13 — Install Python 3.12 (app required newer version)
```bash
dnf list --available 'python3.12*'
dnf install -y python3.12 python3.12-pip python3.12-devel
python3.12 --version
# Output: Python 3.12.x
```
> The requirements needed Python 3.12 features (e.g. X | Y union types).
> Installed Python 3.12 from dnf.

```bash
rm -rf /opt/cloudcart/venv
python3.12 -m venv /opt/cloudcart/venv
source /opt/cloudcart/venv/bin/activate
python --version
which python
# Output: /opt/cloudcart/venv/bin/python  Python 3.12.x
```
> Deleted old venv, recreated with Python 3.12, activated and verified.

```bash
cd /opt/cloudcart/backend
pip install --upgrade pip
pip install -r requirements.txt
```
> Reinstalled all dependencies under Python 3.12.

---

### Step 14 — Start the app manually to test
```bash
cd /opt/cloudcart/backend
uvicorn app.main:app --host 0.0.0.0 --port 8000
```
> Started the FastAPI application manually.
> Verified it started and connected to RDS successfully.
> Tested endpoints with curl from another terminal.

---

### Step 15 — Install and enable systemd service
```bash
cat > /etc/systemd/system/cloudcart.service <<'EOF'
[Unit]
Description=CloudCart FastAPI Application
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ec2-user
Group=ec2-user
WorkingDirectory=/opt/cloudcart/backend
EnvironmentFile=/opt/cloudcart/backend/.env
ExecStart=/opt/cloudcart/venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```
> Created systemd service so the app:
> - Starts automatically on EC2 reboot
> - Restarts automatically if it crashes
> - Reads .env for DB credentials and JWT secret

```bash
chown -R ec2-user:ec2-user /opt/cloudcart
chmod 600 /opt/cloudcart/backend/.env
systemctl daemon-reload
systemctl enable --now cloudcart
systemctl status cloudcart --no-pager
```
> Secured .env with 600 permissions (only ec2-user can read).
> Enabled and started the service. Status showed: active (running).

---

### Step 16 — Verify app is running correctly
```bash
curl http://127.0.0.1:8000/api/health
# Output: {"status":"ok","database":"mysql"}
```
> Health check confirmed: App server running + RDS connected.

```bash
curl http://127.0.0.1:8000/openapi.json
curl http://127.0.0.1:8000/docs
```
> Verified FastAPI auto-generated docs are accessible.

---

### Step 17 — Test API endpoints end-to-end
```bash
# Register first test user
curl -X POST http://127.0.0.1:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"test@cloudcart.com","password":"CloudCart@123"}'
# Output: {"id":1,"email":"test@cloudcart.com"}
```

```bash
# Login with test user
curl -X POST http://127.0.0.1:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@cloudcart.com","password":"CloudCart@123"}'
# Output: {"access_token":"eyJ...","token_type":"bearer"}
```

```bash
# Register main user
curl -X POST http://127.0.0.1:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"manish@cloudcart.com","password":"Manish@123"}'
# Output: {"id":2,"email":"manish@cloudcart.com"}
```
> Both users registered successfully. Passwords stored as argon2id hashes in RDS.

---

### Step 18 — Verify data in RDS
```bash
mysql -h "$DB_HOST" -u "$DB_USER" -p "$DB_NAME"
```
```sql
show tables;
-- order_items, orders, products, users

select * from users;
-- id=1 test@cloudcart.com  (argon2id hash)
-- id=2 manish@cloudcart.com (argon2id hash)

select * from orders;
-- 4 orders placed: ₹2499, ₹2798, ₹3498, ₹2798
```
> Confirmed end-to-end flow: frontend → nginx → ALB → FastAPI → RDS.

---

## ═══════════════════════════════════════════════
## PART 2 — WEB EC2 SETUP
## Instance: Web-Server-1 (ip-192-168-0-209)
## Private IP: 192.168.0.209 | Type: t2.micro
## ═══════════════════════════════════════════════

### Step 1 — Update and install Nginx
```bash
dnf update -y
dnf install -y nginx
```
> Updated packages and installed Nginx on the Web EC2.

---

### Step 2 — Start and enable Nginx
```bash
systemctl enable --now nginx
systemctl status nginx --no-pager
# Output: active (running)
```
> Nginx started and set to auto-start on reboot.

---

### Step 3 — Create frontend directory and pull files from S3
```bash
mkdir -p /var/www/cloudcart/frontend
aws s3 sync s3://3-tier-project-10-09-2026/cloudcart/frontend/ /var/www/cloudcart/frontend/
ls -la /var/www/cloudcart/frontend
chown -R nginx:nginx /var/www/cloudcart
```
> Pulled all frontend files (HTML, CSS, JS) from S3 to the web root.
> Set nginx as the owner so it can serve the files.

---

### Step 4 — Configure Nginx
```bash
nano /etc/nginx/conf.d/cloudcart.conf
```
> Created Nginx site config with:
> - root /var/www/cloudcart/frontend
> - location / → serve static HTML/CSS/JS
> - location /api/ → proxy_pass to Internal ALB DNS
>   (internal-cloudcart-internal-alb-1248576790.ap-south-1.elb.amazonaws.com)

---

### Step 5 — Validate and reload Nginx
```bash
nginx -t
# Output: syntax is ok / test is successful
systemctl restart nginx
```
> Tested config is valid, then restarted Nginx to apply it.

---

### Step 6 — Test locally on web server
```bash
curl http://127.0.0.1/
# Output: CloudCart HTML page served correctly

curl http://127.0.0.1/api/health
# Output: {"status":"ok","database":"mysql"}
```
> Confirmed:
> 1. Nginx serving static frontend files correctly
> 2. /api/* proxy passing through Internal ALB to App tier and back

---

### Step 7 — Debug and verify Nginx config
```bash
sudo nginx -T | grep -A15 -B3 "location /api/"
sudo cat /etc/nginx/conf.d/cloudcart.conf
```
> Inspected the active Nginx configuration to confirm proxy settings.

---

### Step 8 — Verify Internal ALB DNS resolves correctly
```bash
getent hosts internal-cloudcart-internal-alb-1248576790.ap-south-1.elb.amazonaws.com
```
> Confirmed the Internal ALB DNS resolves to private IP addresses inside the VPC.
> This is correct — the Internal ALB is only reachable within the VPC.

---

### Step 9 — Test full chain end-to-end
```bash
curl -v http://127.0.0.1/api/health
# Response headers show:
# < HTTP/1.1 200 OK
# < Connection: keep-alive
# Output: {"status":"ok","database":"mysql"}
```
> Full chain confirmed working:
> Browser → Public ALB → Web EC2 (Nginx) → Internal ALB → App EC2 (FastAPI) → RDS MySQL

---

## ═══════════════════════════════════════════════
## AWS RESOURCES CREATED (Summary)
## ═══════════════════════════════════════════════

### VPC
| Resource | Value |
|----------|-------|
| VPC Name | 3-tier-project-vpc |
| VPC ID | vpc-0aa6c1eec95719a82 |
| CIDR | 192.168.0.0/16 |
| Region | ap-south-1 (Mumbai) |
| DNS Hostnames | Enabled |

### Subnets (6 total)
| Name | Type | CIDR | AZ |
|------|------|------|----|
| 3-tier-project-subnet-WEB-1public1-ap-south-1b | Public | 192.168.0.0/20 | ap-south-1b |
| 3-tier-project-subnet-WEB2-public2-ap-south-1c | Public | 192.168.16.0/20 | ap-south-1c |
| 3-tier-project-subnet-APP-1-private1-ap-south-1b | Private | 192.168.128.0/20 | ap-south-1b |
| 3-tier-project-subnet-APP-2-private2-ap-south-1c | Private | 192.168.144.0/20 | ap-south-1c |
| 3-tier-project-subnet-DB-1-private3-ap-south-1b | Private | 192.168.160.0/20 | ap-south-1b |
| 3-tier-project-subnet-DB-2-private4-ap-south-1c | Private | 192.168.176.0/20 | ap-south-1c |

### Gateways
| Resource | Details |
|----------|---------|
| Internet Gateway | igw-0f6487020ddf87d72 / 3-tier-project-igw — Attached |
| NAT Gateway | nat-0f3311f42efe1f156 / 3-tier-project-nat-public1-ap-south-1b |
| NAT Public IP | 3.108.87.188 |
| NAT Private IP | 192.168.7.45 |

### Security Groups
| Name | Purpose | Key Inbound Rule |
|------|---------|-----------------|
| WebALB-SG | Public Load Balancer | TCP 80/443 from Internet (0.0.0.0/0) |
| Web-SG | Web EC2 (Nginx) | TCP 80 from WebALB-SG only |
| AppALB-SG | Internal Load Balancer | TCP 8000 from Web-SG |
| App-SG | App EC2 (FastAPI) | TCP 8000 from AppALB-SG only |
| Database-SG | RDS MySQL | TCP 3306 from App-SG only |

### EC2 Instances
| Name | ID | Type | AZ | Status |
|------|----|------|----|--------|
| Web-Server-1 | i-00144c305f35891d6 | t2.micro | ap-south-1b | Running ✅ |
| Web-Server-2 | i-00d1c2d40fb2e18e3 | t3.micro | ap-south-1c | Running ✅ |
| APP-Server-1 | i-073bbfec5d98c36ad | t2.micro | ap-south-1b | Running ✅ |
| APP-Server-2 | i-0348ea4f8a4956d97 | t3.micro | ap-south-1c | Running ✅ |

### Load Balancers
| Name | Type | Scheme | Status |
|------|------|--------|--------|
| cloudcart-public-alb | Application | Internet-facing | Active ✅ |
| cloudcart-internal-alb | Application | Internal | Active ✅ |

### Target Groups
| Name | Port | Protocol | Load Balancer |
|------|------|----------|---------------|
| cloudcart-web-tg | 80 | HTTP | cloudcart-public-alb |
| cloudcart-app-tg | 8000 | HTTP | cloudcart-internal-alb |

### RDS Database
| Resource | Value |
|----------|-------|
| Identifier | mydbinstance |
| Engine | MySQL Community 8.4.9 |
| Class | db.t3.micro |
| AZ | ap-south-1b |
| Publicly Accessible | No ✅ |
| Status | Available ✅ |
| Connections | 3 active |

### IAM Role
| Resource | Value |
|----------|-------|
| Role Name | 3-tier-Role |
| Policies | AmazonEC2RoleforSSM + AmazonSSMFullAccess |
| Attached to | All 4 EC2 instances |

### S3 Bucket
| Resource | Value |
|----------|-------|
| Bucket Name | 3-tier-project-10-09-2026 |
| Folders | cloudcart/backend/, frontend/, database/, deployment/ |
| Purpose | Source of truth — all code pulled from here to EC2 |

---

## ═══════════════════════════════════════════════
## FINAL VERIFICATION
## ═══════════════════════════════════════════════

```
✅ Public ALB DNS accessible in browser
✅ Frontend (HTML/CSS/JS) loading correctly
✅ /api/health → {"status":"ok","database":"mysql"}
✅ User registration working (argon2id password hashing)
✅ User login working (JWT token returned)
✅ Products loading from RDS
✅ Add to cart working (localStorage)
✅ Checkout / order creation working
✅ Orders stored in RDS (4 real orders confirmed)
✅ RDS NOT publicly accessible (private subnet only)
✅ App EC2 NOT directly reachable from internet
✅ All 4 EC2 status checks passing (2/2 or 3/3)
✅ systemd service auto-restarts FastAPI on crash/reboot
```

---

## ⚠️ Next Steps (TODO)

1. **Add HTTPS** — Request ACM certificate, attach to cloudcart-public-alb on port 443, add HTTP→HTTPS redirect rule
2. **Move DB credentials to AWS Secrets Manager** — Remove plaintext .env and fetch at runtime
3. **Enable RDS Multi-AZ** — For high availability and automatic failover
4. **Add CloudWatch Alarms** — CPU, memory, RDS connections, ALB 5xx errors
5. **Set up Auto Scaling Groups** — For Web and App tiers to scale under load
