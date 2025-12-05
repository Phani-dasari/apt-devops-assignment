# Apt DevOps Assignment – One Click Deployment

This project deploys a simple Python Flask REST API on private EC2 instances
behind an Application Load Balancer (ALB) and Auto Scaling Group (ASG) using Terraform.

## Architecture

Client → ALB (public subnets) → Target Group → ASG → EC2 (private subnets) → NAT → IGW

- VPC with 2 public + 2 private subnets
- Internet Gateway and NAT Gateway
- ALB HTTP (port 80)
- Target group on port 8080, health check /health
- Auto Scaling Group in private subnets (no public IPs)
- EC2 user-data installs and runs Flask app on port 8080

## REST API

- GET / → Hello from Apt DevOps assignment!
- GET /health → ok

## How to deploy (CloudShell)

```bash
git clone https://github.com/Phani-dasari/apt-devops-assignment.git
cd apt-devops-assignment
chmod +x scripts/deploy.sh scripts/destroy.sh
./scripts/deploy.sh
