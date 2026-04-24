variable "aws_region" {
  description = "AWS region where all resources will be provisioned"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Prefix applied to all resource names for easy identification and cost allocation"
  type        = string
  default     = "aws-provisioning"
}

variable "instance_type" {
  description = "EC2 instance type — t3.micro qualifies for AWS free tier (750 h/month)"
  type        = string
  default     = "t3.micro"
}

variable "managed_node_count" {
  description = "Number of EC2 instances that will be provisioned by the Ansible playbook"
  type        = number
  default     = 2
}

variable "public_key_path" {
  description = "Path to SSH public key uploaded to AWS as a key pair"
  type        = string
  default     = "~/.ssh/ansible-aws-provisioning.pub"
}

variable "private_key_path" {
  description = "Path to SSH private key written into the generated Ansible inventory"
  type        = string
  default     = "~/.ssh/ansible-aws-provisioning"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to reach port 22 — restrict to your IP in production (e.g. 1.2.3.4/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "app_port" {
  description = "Application port exposed by nginx"
  type        = number
  default     = 8080
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "sandbox"
}
