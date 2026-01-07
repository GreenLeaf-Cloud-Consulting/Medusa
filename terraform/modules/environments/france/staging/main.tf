data "aws_vpc" "default" {
  default = true
}

module "ec2" {
  instance_name   = "france-instance"
  source          = "../../../ec2-instance"
  ami             = "ami-0359cb6c0c97c6607"
  instance_type   = "t3.small"
  environment     = "staging"
  allowed_ports   = [22, 80, 443]
  region          = "eu-west-3"
  ssh_user        = "admin"
}

output "instance_ip" {
  value = module.ec2.instance_ip
}

output "ssh_private_key" {
  value     = module.ec2.ssh_private_key
  sensitive = true
}