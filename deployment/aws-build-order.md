# AWS CloudCart Build Order

1. Create VPC 10.0.0.0/16.
2. Create two public subnets:
   - 10.0.0.0/20 in us-east-1a
   - 10.0.16.0/20 in us-east-1b
3. Create two private application subnets:
   - 10.0.128.0/20 in us-east-1a
   - 10.0.144.0/20 in us-east-1b
4. Create two private database subnets:
   - 10.0.160.0/20 in us-east-1a
   - 10.0.176.0/20 in us-east-1b
5. Attach Internet Gateway.
6. Create NAT Gateway in a public subnet with an Elastic IP.
7. Configure public and private route tables.
8. Create Bastion Host in a public subnet.
9. Create security groups according to deployment/security-groups.md.
10. Create two Web EC2 instances in public subnets.
11. Install Nginx and deploy frontend on Web EC2.
12. Create the Internal Application Load Balancer in private subnets.
13. Create two Application EC2 instances in private application subnets.
14. Install Python/FastAPI/Uvicorn and deploy backend.
15. Point Web Nginx /api/ traffic to the Internal ALB DNS.
16. Create an RDS MySQL instance in the database subnet group.
17. Set RDS public access to No.
18. Allow TCP 3306 only from appserver-sg.
19. Run database/schema.sql against RDS.
20. Create the Public ALB in the two public subnets.
21. Public ALB target group -> Web EC2 instances on port 80.
22. Public ALB listener -> target group.
23. Internal ALB target group -> App EC2 instances on port 8000.
24. Internal ALB listener -> target group.
25. Test:
    - Public ALB -> CloudCart frontend
    - /api/health -> {"status":"ok","database":"mysql"}
    - /api/products -> seeded products
    - Login/register
    - Cart/checkout
26. Add HTTPS using ACM on the Public ALB.
