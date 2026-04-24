terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

locals {
  # Mandatory tags enforced by platform-engineering governance policy
  common_tags = {
    "fo:owner"       = "sabatino"
    "fo:platform"    = "platform-engineering"
    "fo:environment" = "sandbox"
    "fo:purpose"     = "poc-runbooks"
    "Project"        = var.project_name
    "ManagedBy"      = "terraform"
  }
}

# Always fetch the latest Ubuntu 22.04 LTS AMI published by Canonical
# Canonical's AWS account ID is 099720109477 — using it prevents impostor AMIs
data "aws_ami" "ubuntu_2204" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_key_pair" "provisioning" {
  key_name   = "${var.project_name}-key"
  public_key = file(pathexpand(var.public_key_path))

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-key"
  })
}

resource "aws_security_group" "provisioning" {
  name        = "${var.project_name}-sg"
  description = "Allow SSH and HTTP inbound; all outbound for AWS provisioning"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH access - restrict allowed_ssh_cidr to your IP in production"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "HTTP access for nginx application"
    from_port   = var.app_port
    to_port     = var.app_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound - required for apt package installation"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-sg"
  })
}

# Control node runs Ansible and boto3 — heavier package footprint
resource "aws_instance" "control_node" {
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.provisioning.key_name
  vpc_security_group_ids      = [aws_security_group.provisioning.id]
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 12
    delete_on_termination = true
  }

  # Cloud-init installs Ansible toolchain so the control node is ready immediately
  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3 python3-pip ansible
    pip3 install boto3 botocore
    ansible-galaxy collection install amazon.aws community.aws
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-control"
    Role = "control"
  })
}

# Managed nodes are provisioning targets — only python3 is required for Ansible
resource "aws_instance" "managed_nodes" {
  count                       = var.managed_node_count
  ami                         = data.aws_ami.ubuntu_2204.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.provisioning.key_name
  vpc_security_group_ids      = [aws_security_group.provisioning.id]
  subnet_id                   = data.aws_subnets.default.ids[0]
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
  }

  user_data = <<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y python3
  EOF

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-managed-${count.index + 1}"
    Role = "managed"
    Index = tostring(count.index + 1)
  })
}

# Render the Ansible inventory and write it outside the terraform/ directory
# so Ansible can consume it without needing to navigate into the subdirectory
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    control_ip         = aws_instance.control_node.public_ip
    managed_node_ips   = aws_instance.managed_nodes[*].public_ip
    private_key_path   = pathexpand(var.private_key_path)
  })
  filename        = "${path.module}/../inventory/hosts.ini"
  file_permission = "0644"
}
