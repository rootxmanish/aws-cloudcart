# CloudCart — AWS 3-Tier E-Commerce Project

## Architecture

Internet
  |
  v
Public Application Load Balancer
  |
  +--------------------+
  |                    |
Web EC2 AZ-1       Web EC2 AZ-2
Nginx               Nginx
  |                    |
  +---------+----------+
            |
            v
Internal Application Load Balancer
            |
      +-----+-----+
      |           |
 App EC2 AZ-1  App EC2 AZ-2
 FastAPI       FastAPI
 Uvicorn       Uvicorn
      |           |
      +-----+-----+
            |
            v
      Amazon RDS MySQL
       Private Subnets

Bastion Host -> administration access to private EC2 instances
NAT Gateway -> outbound internet access for private EC2 instances

## AWS traffic rules

Internet -> Public ALB: TCP 80/443
Public ALB -> Web EC2: TCP 80
Web EC2 -> Internal ALB: TCP 8000
Internal ALB -> App EC2: TCP 8000
App EC2 -> RDS MySQL: TCP 3306
Bastion -> Web/App EC2: TCP 22

RDS must NOT be publicly accessible.
App EC2 must NOT be directly reachable from the internet.
Web EC2 should not allow HTTP from 0.0.0.0/0; allow it from the Public ALB security group.

## Project structure

frontend/
  index.html
  products.html
  cart.html
  login.html
  css/style.css
  js/app.js

backend/
  app/
    main.py
    database/connection.py
    models/models.py
    schemas/schemas.py
    routes/auth.py
    routes/products.py
    routes/orders.py
    services/auth.py
  requirements.txt
  .env.example
  nginx/cloudcart-web.conf
  systemd/cloudcart.service

database/
  schema.sql

deployment/
  web/setup-web.sh
  app/setup-app.sh
  web/nginx-cloudcart.conf.template
  security-groups.md
  aws-build-order.md

## Local development

Use the existing shared virtual environment if desired:

E:\DevOps\python\devops-env\Scripts\Activate.ps1

Then from backend:

pip install -r requirements.txt

Set environment variables from .env.example and run:

uvicorn app.main:app --reload

For AWS, the application should run behind the internal ALB.

## Screenshots

Deployment screenshots are in the `screenshots/` folder.

| File | What it shows |
|------|--------------|
| `website.png` | Live CloudCart site via Public ALB |
| `all-servers.png` | 4 EC2 instances running (APP-1, APP-2, Web-1, Web-2) |
| `load-balancer.png` | Public ALB + Internal ALB — both Active |
| `target-group.png` | cloudcart-web-tg (port 80) + cloudcart-app-tg (port 8000) |
| `database.png` | RDS MySQL mydbinstance — Available, not publicly accessible |
| `database-output.png` | MySQL shell — tables, orders, users with argon2 hashes |
| `vpc.png` | VPC resource map — subnets, route tables, IGW, NAT |
| `subnet.png` | 6 subnets across ap-south-1b and ap-south-1c |
| `route-tables.png` | 5 custom route tables (public + 4 private) |
| `security-group.png` | App-SG, Web-SG, Database-SG, WebALB-SG, AppALB-SG |
| `nat-gateway.png` | NAT Gateway — Available, EIP 3.108.87.188 |
| `internet-gateway.png` | IGW attached to 3-tier-project-vpc |
| `iam-role.png` | 3-tier-Role with AmazonEC2RoleforSSM + AmazonSSMFullAccess |
| `s3-bucket.png` | S3 bucket with backend/, frontend/, database/, deployment/ |

## Important

This project intentionally does NOT use Docker or Terraform.

Before production:
- Use HTTPS with ACM on the public ALB.
- Store DB credentials in AWS Secrets Manager or SSM Parameter Store.
- Restrict CORS.
- Use IAM roles instead of long-lived AWS access keys.
- Enable RDS backups, Multi-AZ as required, monitoring and encryption.
