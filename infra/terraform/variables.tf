variable "region" {
  description = "AWS region to provision into."
  type        = string
  default     = "eu-west-1"
}

variable "vpc_name" {
  description = "Name tag of the existing shared VPC to deploy into."
  type        = string
  default     = "development"
}

variable "public_subnet_name" {
  description = "Name tag of the public subnet to host the EC2 instance."
  type        = string
  default     = "development-public-eu-west-1a"
}

variable "rds_subnet_name_prefix" {
  description = "Prefix of the private subnet name tags used for the RDS subnet group."
  type        = string
  default     = "RDS-Pvt-subnet-"
}

variable "owner_email" {
  description = "Email used for resource Owner tag and Let's Encrypt registration."
  type        = string
  default     = "ivan.zakharanka@airhelp.com"
}

variable "project_name" {
  description = "Project tag applied to all resources."
  type        = string
  default     = "auth-service-learning"
}

variable "name_prefix" {
  description = "Prefix used for AWS resource names (keeps them identifiable in a shared account)."
  type        = string
  default     = "ivan-auth-learning"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to import as the EC2 key pair."
  type        = string
  default     = "~/.ssh/aws_learning_ed25519.pub"
}

variable "ec2_instance_type" {
  description = "EC2 instance type. t4g = ARM64 Graviton."
  type        = string
  default     = "t4g.small"
}

variable "ec2_root_volume_size" {
  description = "Size of the EC2 root EBS volume in GiB."
  type        = number
  default     = 20
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "rds_allocated_storage" {
  description = "RDS storage size in GiB."
  type        = number
  default     = 20
}

variable "rds_engine_version" {
  description = "PostgreSQL engine version."
  type        = string
  default     = "16.13"
}

variable "db_name" {
  description = "Initial database name created on RDS."
  type        = string
  default     = "auth_service"
}

variable "db_username" {
  description = "Master username for RDS."
  type        = string
  default     = "dbadmin"
}

variable "my_ip_override" {
  description = "Override your current public IP for SSH / kube-api access. Leave null to auto-detect via checkip.amazonaws.com."
  type        = string
  default     = null
}
