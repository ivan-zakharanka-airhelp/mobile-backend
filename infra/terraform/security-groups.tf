# ── EC2 security group ──
# SSH + Kubernetes API: your IP only
# HTTP + HTTPS: public (Traefik ingress)

resource "aws_security_group" "ec2" {
  name        = "${var.name_prefix}-ec2"
  description = "EC2 for auth-service learning - SSH from operator, HTTP/HTTPS public."
  vpc_id      = data.aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-ec2"
  })
}

resource "aws_vpc_security_group_ingress_rule" "ec2_ssh" {
  security_group_id = aws_security_group.ec2.id
  description       = "SSH from operator"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = local.my_ip_cidr
}

resource "aws_vpc_security_group_ingress_rule" "ec2_kube_api" {
  security_group_id = aws_security_group.ec2.id
  description       = "k3s API from operator"
  ip_protocol       = "tcp"
  from_port         = 6443
  to_port           = 6443
  cidr_ipv4         = local.my_ip_cidr
}

resource "aws_vpc_security_group_ingress_rule" "ec2_http" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTP (Traefik + LetsEncrypt HTTP-01 challenge)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ec2_https" {
  security_group_id = aws_security_group.ec2.id
  description       = "HTTPS (Traefik)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "ec2_all" {
  security_group_id = aws_security_group.ec2.id
  description       = "All egress"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

# ── RDS security group ──
# Postgres only from the EC2 security group (not from CIDR).

resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-rds"
  description = "RDS for auth-service learning - Postgres from EC2 SG only."
  vpc_id      = data.aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-rds"
  })
}

resource "aws_vpc_security_group_ingress_rule" "rds_postgres_from_ec2" {
  security_group_id            = aws_security_group.rds.id
  description                  = "Postgres from auth-service EC2 SG"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.ec2.id
}

resource "aws_vpc_security_group_egress_rule" "rds_all" {
  security_group_id = aws_security_group.rds.id
  description       = "All egress"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}
