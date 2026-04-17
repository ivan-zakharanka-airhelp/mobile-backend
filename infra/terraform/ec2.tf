# ── EC2 instance + Elastic IP ──
#
# Flow:
#   1. aws_eip.main allocated first.
#   2. aws_instance.main launched; cloud-init user_data fetches its own public IP
#      from EC2 metadata — but at first boot that's the EC2-assigned public IP,
#      NOT yet the Elastic IP.
#   3. aws_eip_association.main swaps the public IP to the EIP.
#   4. cloud-init installs k3s with --tls-san set to whatever was the public IP
#      at boot. Since the EIP association can lag, we explicitly refresh k3s's
#      TLS certs post-association from the bootstrap script.
#
# Simpler design choice: pass the EIP address as a template variable into
# cloud-init. Terraform can do this because the EIP address is known before
# the instance is created.

resource "aws_eip" "main" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-eip"
  })
}

resource "aws_instance" "main" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.ec2_instance_type
  subnet_id              = data.aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  key_name               = aws_key_pair.deploy.key_name

  associate_public_ip_address = true

  # Require IMDSv2 (more secure; modern AWS default for new AMIs)
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.ec2_root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(local.common_tags, {
      Name = "${var.name_prefix}-root"
    })
  }

  user_data = templatefile("${path.module}/cloud-init.yaml", {
    public_ip = aws_eip.main.public_ip
  })

  # Re-run cloud-init when user_data changes (e.g. new EIP → new --tls-san).
  user_data_replace_on_change = true

  tags = merge(local.common_tags, {
    Name = var.name_prefix
  })

  lifecycle {
    # Avoid spurious replacements if Canonical publishes a new AMI mid-session.
    ignore_changes = [ami]
  }
}

resource "aws_eip_association" "main" {
  instance_id   = aws_instance.main.id
  allocation_id = aws_eip.main.id
}
