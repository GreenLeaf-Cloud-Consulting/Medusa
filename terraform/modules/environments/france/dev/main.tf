data "aws_vpc" "default" {
  default = true
}

module "ec2" {
  instance_name   = "france-instance"
  source          = "../../../ec2-instance"
  ami             = "ami-0359cb6c0c97c6607"
  instance_type   = "t3.micro"
  environment     = "dev"
  allowed_ports   = [22, 80]
  region          = "eu-west-3"
  ssh_user        = "admin"
}

resource "aws_eip" "dev_eip" {
  instance = module.ec2.instance_id
  tags = {
    Environment = "dev"
  }
}

output "instance_ip" {
  value = module.ec2.instance_ip
}

output "ssh_private_key" {
  value     = module.ec2.ssh_private_key
  sensitive = true
}