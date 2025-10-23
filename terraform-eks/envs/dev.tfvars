region_name = "ap-south-1"
aws_account_id = "868295556072"
cluster_version = "1.31"
vpc_cidr = "10.0.0.0/16"
azs = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
public_subnets_range = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets_range = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
intra_subnets_range = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
nat_gateway = true
single_nat_gateway = true
one_nat_gateway_per_az = false
enable_dns_support = true
enable_efs_storage = true
node_group_name = "eks-karpenter-mng"
cluster_name = "dev-new-eks-karpenter"
environment = "dev"
enable_eks_public_access = true
enable_eks_private_access = true
enable_admin_permissions = true
irsa = true
node_instance_type = "t3.medium"
node_ami_type = "AL2023_x86_64_STANDARD"
min_size = 2
max_size = 5
desired_size = 3
disk_size = 50
tags = {
  Environment = "dev"
  Project     = "eks-karpenter"
  ManagedBy   = "terraform"
}
instance_profile = true

node_iam_role_additional_policies = {
  AmazonSSMManagedInstanceCore       = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  AmazonEKSWorkerNodePolicy         = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  AmazonEKS_CNI_Policy              = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

karpenter_controller_policy_statements = [
  {
    Effect = "Allow"
    Action = [
      "ec2:CreateFleet",
      "ec2:CreateLaunchTemplate",
      "ec2:CreateTags",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeImages",
      "ec2:DescribeInstances",
      "ec2:DescribeInstanceTypeOfferings",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSpotPriceHistory",
      "ec2:DescribeSubnets",
      "ec2:DeleteLaunchTemplate",
      "ec2:RunInstances",
      "ec2:TerminateInstances"
    ]
    Resource = "*"
  },
  {
    Effect = "Allow"
    Action = [
      "iam:PassRole"
    ]
    Resource = "NODE_IAM_ROLE_ARN"
  },
  {
    Effect = "Allow"
    Action = [
      "eks:DescribeCluster"
    ]
    Resource = "CLUSTER_ARN"
  },
  {
    Effect = "Allow"
    Action = [
      "iam:GetInstanceProfile"
    ]
    Resource = "*"
  },
  {
    Effect = "Allow"
    Action = [
      "pricing:GetProducts"
    ]
    Resource = "*"
  },
  {
    Effect = "Allow"
    Action = [
      "ssm:GetParameter"
    ]
    Resource = "arn:aws:ssm:*:*:parameter/aws/service/*"
  },
  {
    Effect = "Allow"
    Action = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage"
    ]
    Resource = "QUEUE_ARN"
  }
]
karpenter_capacity_types = ["on-demand"]
karpenter_instance_types = ["m5.large", "m5.xlarge", "m5.2xlarge", "c5.large", "c5.xlarge", "r5.large", "r5.xlarge"]
karpenter_cpu_limit = 1000
karpenter_ttl_seconds_after_empty = 30
