################################################################################
# AWS — VPC
################################################################################
module "aws_vpc" {
  source = "../../../modules/aws/vpc"

  name             = var.eks_cluster_name
  cidr             = var.vpc_cidr
  eks_cluster_name = var.eks_cluster_name

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]
  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
}

################################################################################
# AWS — EKS Cluster 1
################################################################################
module "eks" {
  source = "../../../modules/aws/eks"

  cluster_name       = var.eks_cluster_name
  kubernetes_version = "1.30"

  vpc_id             = module.aws_vpc.vpc_id
  private_subnet_ids = module.aws_vpc.private_subnet_ids
  public_subnet_ids  = module.aws_vpc.public_subnet_ids

  node_instance_type = var.eks_node_instance_type
  node_desired       = 1
  node_min           = 1
  node_max           = 1

  depends_on = [module.aws_vpc]
}

################################################################################
# AWS — EC2 VM (se unirá al mesh de Istio del Cluster 1)
################################################################################
module "ec2_vm" {
  source = "../../../modules/aws/ec2-vm"

  name                = "sre-sender-vm"
  instance_type       = "t3.micro"
  vpc_id              = module.aws_vpc.vpc_id
  subnet_id           = module.aws_vpc.private_subnet_ids[0]
  vpc_cidr            = module.aws_vpc.vpc_cidr
  ssh_public_key_path = var.ssh_public_key_path

  depends_on = [module.aws_vpc]
}
