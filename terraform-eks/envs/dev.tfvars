aws_region  = "ap-south-1"
cluster_version = "1.33"
vpc_cidr    = "10.0.0.0/16"
azs         = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
node_group_name = "default"
enable_efs_storage = true
project     = "eks-karpenter"

cluster_name = "dev-eks-karpenter-cluster"
environment = "dev"
node_group_min_size = 2
node_group_max_size = 5
node_group_desired_size = 3
node_group_instance_types = ["t3.medium"]
node_group_disk_size = 50

# Optional: Override default tags
tags = {
  Environment = "dev"
  Project     = "eks-karpenter"
  ManagedBy   = "terraform"
}
