output "eks_cluster_name" {
  value       = module.eks.cluster_name
  description = "aws eks update-kubeconfig --name <valor> --region us-east-1 --alias cluster1-eks"
}

output "eks_cluster_endpoint" {
  value     = module.eks.cluster_endpoint
  sensitive = true
}

output "vpc_id" {
  value = module.aws_vpc.vpc_id
}

output "vpc_cidr" {
  value = module.aws_vpc.vpc_cidr
}

output "vm_private_ip" {
  value       = module.ec2_vm.private_ip
  description = "Copiar a addons/istio/cluster1-eks/workload-entry.yaml (campo address)"
}

output "vm_public_ip" {
  value       = module.ec2_vm.public_ip
  description = "SSH: ssh -i ~/.ssh/id_rsa ec2-user@<valor>"
}
