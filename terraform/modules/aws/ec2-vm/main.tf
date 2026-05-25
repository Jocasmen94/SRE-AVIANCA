################################################################################
# IAM Role para SSM (Systems Manager)
################################################################################
resource "aws_iam_role" "vm" {
  name = "${var.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.vm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "vm" {
  name = "${var.name}-profile"
  role = aws_iam_role.vm.name
}

################################################################################
# Key Pair
################################################################################
resource "aws_key_pair" "vm" {
  key_name   = "${var.name}-key"
  public_key = file(pathexpand(var.ssh_public_key_path))
}

################################################################################
# Security Group
################################################################################
resource "aws_security_group" "vm" {
  name        = "${var.name}-sg"
  description = "EC2 VM for Istio mesh workload"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Istio outbound"
    from_port   = 15001
    to_port     = 15001
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Istio inbound"
    from_port   = 15006
    to_port     = 15006
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Istio HBONE"
    from_port   = 15008
    to_port     = 15008
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Istio agent xDS"
    from_port   = 15012
    to_port     = 15012
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.name}-sg" }
}

################################################################################
# Latest Amazon Linux 2023 AMI
################################################################################
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

################################################################################
# EC2 Instance
################################################################################
resource "aws_instance" "vm" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.vm.id]
  key_name               = aws_key_pair.vm.key_name
  iam_instance_profile   = aws_iam_instance_profile.vm.name

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
  }

  tags = { Name = var.name }
}

################################################################################
# Elastic IP — needed for SSH and Istio agent to reach EKS API server
################################################################################
resource "aws_eip" "vm" {
  instance   = aws_instance.vm.id
  domain     = "vpc"
  depends_on = [aws_instance.vm]
  tags       = { Name = "${var.name}-eip" }
}
