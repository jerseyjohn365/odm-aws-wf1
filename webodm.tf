#-------------------------------
# AWS Provider
#-------------------------------
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Name    = var.repo_name
      Owner   = var.repo_owner
      Project = var.project
    }
  }
}
#-------------------------------
# S3 Remote State
#-------------------------------
terraform {
  backend "s3" {
    # bucket is injected at init time via -backend-config="bucket=$BUCKET"
    key    = "terraform.tfstate"
    region = "us-east-2"
  }
}
#-------------------------------
# VPC
#-------------------------------
resource "aws_vpc" "odm" {
  cidr_block = var.vpc_cidr_block
}
resource "aws_subnet" "odm_public_subnet" {
  vpc_id            = aws_vpc.odm.id
  cidr_block        = var.public_subnet
  availability_zone = var.avail_zone
}
#-------------------------------
# Internet Gateway
#-------------------------------
resource "aws_internet_gateway" "odm" {
  vpc_id = aws_vpc.odm.id
}
#-------------------------------
# Route Tables
#-------------------------------
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.odm.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.odm.id
  }
  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.odm.id
  }
}
resource "aws_route_table_association" "public_1_rt_a" {
  subnet_id      = aws_subnet.odm_public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}
#-------------------------------
# Security Group — outbound only, no inbound needed
#-------------------------------
resource "aws_security_group" "odm" {
  name   = "ODM processing"
  vpc_id = aws_vpc.odm.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
#-------------------------------
# IAM — instance profile grants S3 read/write
#-------------------------------
resource "aws_iam_role" "odm_instance" {
  name = "${var.repo_name}-instance-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}
resource "aws_iam_role_policy" "odm_s3" {
  name = "${var.repo_name}-s3-access"
  role = aws_iam_role.odm_instance.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ]
      Resource = [
        "arn:aws:s3:::${var.data_bucket}",
        "arn:aws:s3:::${var.data_bucket}/*"
      ]
    }]
  })
}
resource "aws_iam_instance_profile" "odm" {
  name = "${var.repo_name}-instance-profile"
  role = aws_iam_role.odm_instance.name
}
#-------------------------------
# AMI — latest Ubuntu 22.04 LTS
#-------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}
#-------------------------------
# EC2 — ODM processing instance
#-------------------------------
resource "aws_instance" "odm" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = lookup(var.instance_type, var.type_selector)
  subnet_id                   = aws_subnet.odm_public_subnet.id
  vpc_security_group_ids      = [aws_security_group.odm.id]
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.odm.name
  user_data                   = templatefile("odm.tpl", {
    data_bucket   = var.data_bucket
    input_prefix  = var.input_prefix
    output_prefix = var.output_prefix
  })
  root_block_device {
    volume_size = var.rootBlockSize
  }
}
