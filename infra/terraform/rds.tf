resource "random_password" "db" {
  length           = 24
  special          = false # alphanumeric only — avoids quoting pain in connection strings
  override_special = ""
}

resource "aws_db_subnet_group" "main" {
  name        = "${var.name_prefix}-db-subnets"
  description = "Subnet group for ${var.name_prefix} RDS"
  subnet_ids  = data.aws_subnets.rds_private.ids

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-db-subnets"
  })
}

resource "aws_db_instance" "main" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = var.rds_engine_version
  instance_class = var.rds_instance_class

  allocated_storage     = var.rds_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true
  max_allocated_storage = 0 # disable autoscaling for learning project

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  vpc_security_group_ids = [aws_security_group.rds.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  backup_retention_period = 1
  publicly_accessible     = false
  multi_az                = false

  # Learning-project ergonomics: easy destroy, fast in-place changes.
  skip_final_snapshot        = true
  apply_immediately          = true
  deletion_protection        = false
  auto_minor_version_upgrade = false

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-db"
  })
}
