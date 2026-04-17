# ── Networking lookups: use existing AirHelp development VPC ──

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = [var.vpc_name]
  }
}

data "aws_subnet" "public" {
  vpc_id = data.aws_vpc.main.id

  filter {
    name   = "tag:Name"
    values = [var.public_subnet_name]
  }
}

data "aws_subnets" "rds_private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Name"
    values = ["${var.rds_subnet_name_prefix}*"]
  }
}

# ── Latest Ubuntu 24.04 ARM64 AMI (Canonical) ──

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-arm64-server-*"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── Auto-detect operator's public IP for SSH/kube-api ingress rules ──

data "http" "my_ip" {
  count = var.my_ip_override == null ? 1 : 0
  url   = "https://checkip.amazonaws.com"
}

locals {
  my_ip_cidr = var.my_ip_override != null ? "${var.my_ip_override}/32" : "${chomp(data.http.my_ip[0].response_body)}/32"
}
