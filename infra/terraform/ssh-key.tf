resource "aws_key_pair" "deploy" {
  key_name   = var.name_prefix
  public_key = file(pathexpand(var.ssh_public_key_path))

  tags = merge(local.common_tags, {
    Name = var.name_prefix
  })
}
