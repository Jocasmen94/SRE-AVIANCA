output "private_ip" {
  value       = aws_instance.vm.private_ip
  description = "Use this as WorkloadEntry address in the Istio mesh"
}

output "public_ip" {
  value       = aws_eip.vm.public_ip
  description = "Use for SSH: ssh -i ~/.ssh/id_rsa ec2-user@<value>"
}

output "instance_id" {
  value = aws_instance.vm.id
}

output "security_group_id" {
  value = aws_security_group.vm.id
}
