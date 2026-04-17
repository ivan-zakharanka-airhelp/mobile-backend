output "public_ip" {
  description = "Elastic IP of the EC2 instance."
  value       = aws_eip.main.public_ip
}

output "sslip_hostname" {
  description = "Hostname via sslip.io that resolves to public_ip (dashes replace dots)."
  value       = "${replace(aws_eip.main.public_ip, ".", "-")}.sslip.io"
}

output "rds_endpoint" {
  description = "RDS endpoint hostname."
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS port."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Initial database name."
  value       = aws_db_instance.main.db_name
}

output "db_username" {
  description = "Master DB username."
  value       = aws_db_instance.main.username
}

output "db_password" {
  description = "Master DB password (use `terraform output -raw db_password`)."
  value       = random_password.db.result
  sensitive   = true
}

output "ssh_command" {
  description = "Ready-to-copy SSH command (uses the private key matching ssh_public_key_path)."
  value       = "ssh -i ${replace(var.ssh_public_key_path, ".pub", "")} ubuntu@${aws_eip.main.public_ip}"
}

output "health_url" {
  description = "Health endpoint URL (valid ~60s after first deploy)."
  value       = "https://${replace(aws_eip.main.public_ip, ".", "-")}.sslip.io/api/health"
}
