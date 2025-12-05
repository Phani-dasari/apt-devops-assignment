terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az1 = data.aws_availability_zones.available.names[0]
  az2 = data.aws_availability_zones.available.names[1]
}

# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "apt-devops-vpc" }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "apt-devops-igw" }
}

# Public subnets (2)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(["10.0.1.0/24", "10.0.2.0/24"], count.index)
  availability_zone       = element([local.az1, local.az2], count.index)
  map_public_ip_on_launch = true

  tags = { Name = "apt-devops-public-${count.index}" }
}

# Private subnets (2)
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(["10.0.11.0/24", "10.0.12.0/24"], count.index)
  availability_zone = element([local.az1, local.az2], count.index)

  tags = { Name = "apt-devops-private-${count.index}" }
}

# NAT Gateway
resource "aws_eip" "nat" {
  vpc  = true
  tags = { Name = "apt-devops-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  depends_on    = [aws_internet_gateway.igw]
  tags          = { Name = "apt-devops-nat" }
}

# Route table public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "apt-devops-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route table private
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = { Name = "apt-devops-private-rt" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Security groups
resource "aws_security_group" "alb_sg" {
  name        = "apt-devops-alb-sg"
  description = "ALB SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "apt-devops-ec2-sg"
  description = "EC2 SG"
  vpc_id      = aws_vpc.main.id

  # Only ALB can talk to app on 8080
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# IAM role
resource "aws_iam_role" "ec2_role" {
  name = "apt-devops-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "apt-devops-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# User data to run app
locals {
  user_data = <<-EOF
    #!/bin/bash
    set -xe
    apt-get update -y
    apt-get install -y python3 python3-pip git

    cd /opt
    git clone https://github.com/Phani-dasari/apt-devops-assignment.git || true
    cd apt-devops-assignment/app

    pip3 install -r requirements.txt
    nohup python3 main.py > /var/log/app.log 2>&1 &
  EOF
}

# Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Launch template
resource "aws_launch_template" "app" {
  name_prefix   = "apt-devops-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2_profile.name
  }

  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  user_data              = base64encode(local.user_data)
}

# ALB + TG + listener
resource "aws_lb" "app" {
  name               = "apt-devops-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [for s in aws_subnet.public : s.id]
}

resource "aws_lb_target_group" "app" {
  name     = "apt-devops-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/health"
    matcher             = "200"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 30
    timeout             = 5
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "app" {
  name                = "apt-devops-asg"
  desired_capacity    = 1
  max_size            = 2
  min_size            = 1
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "EC2"
  health_check_grace_period = 60

  tag {
    key                 = "Name"
    value               = "apt-devops-ec2"
    propagate_at_launch = true
  }

  depends_on = [aws_lb_listener.http]
}
