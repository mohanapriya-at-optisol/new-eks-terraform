output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "EKS cluster certificate authority data"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = module.eks.cluster_arn
}

output "cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "private_subnets" {
  description = "Private subnet IDs"
  value       = module.vpc.private_subnets
}

output "karpenter_node_role_arn" {
  description = "Karpenter node IAM role ARN"
  value       = module.eks_karpenter.node_iam_role_arn
}

output "karpenter_instance_profile_name" {
  description = "Karpenter instance profile name"
  value       = module.eks_karpenter.instance_profile_name
}

output "configure_kubectl" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --region ${var.region_name} --name ${module.eks.cluster_name} --profile tf-admin"
}
output "efs_id" {
  description = "EFS File System ID"
  value       = aws_efs_file_system.eks.id
}

output "efs_dns_name" {
  description = "EFS DNS name for mounting"
  value       = aws_efs_file_system.eks.dns_name
}

