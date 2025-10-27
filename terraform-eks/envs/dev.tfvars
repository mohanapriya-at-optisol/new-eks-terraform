region_name = "ap-south-1"
aws_account_id = "868295556072"
cluster_version = "1.31"
vpc_cidr = "10.0.0.0/16"
azs = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
public_subnets_range = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets_range = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
intra_subnets_range = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
private_subnet_name = "private_subnet"
public_subnet_name = "public_subnet"
intra_subnet_name = "intra_subnet"
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
kms_alias = "new-kms-key"
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
karpenter_repo = "https://charts.karpenter.sh"
helm_chart_name = "karpenter"
karpenter_version = 0.16.3
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
helm_create_ns = true
karpenter_capacity_types = ["on-demand"]
karpenter_instance_types = ["m5.large", "m5.xlarge", "m5.2xlarge", "c5.large", "c5.xlarge", "r5.large", "r5.xlarge"]
karpenter_cpu_limit = 1000
karpenter_ttl_seconds_after_empty = 30
karpenter_provisioner_name = default
karpenter_provider_ref_name = default
karpenter_node_template_name = deafult
security_group_additional_rules = [
  {
    name                       = "ingress_nodes_ephemeral_ports_tcp"
    description                = "Allow nodes on ephemeral ports"
    from_port                  = 1025
    to_port                    = 65535
    protocol                   = "tcp"
    type                       = "ingress"
    source_node_security_group = true
    cidr_blocks                = []
  },
  {
    name                       = "ingress_admin_api"
    description                = "Allow admin API access"
    from_port                  = 443
    to_port                    = 443
    protocol                   = "tcp"
    type                       = "ingress"
    source_node_security_group = false
    cidr_blocks                = ["203.0.113.0/24"]
  },
  {
    name                       = "egress_all"
    description                = "Allow all outbound traffic"
    from_port                  = 0
    to_port                    = 0
    protocol                   = "-1"
    type                       = "egress"
    source_node_security_group = false
    cidr_blocks                = ["0.0.0.0/0"]
  }
]

node_security_group_additional_rules = {
  ingress_self_all = {
    description = "Allow node-to-node all ports/protocols"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    type        = "ingress"
    self        = true
    cidr_blocks = []  # empty since we're using 'self'
  }

}
efs_sg_name = "efs-sg"
efs_security_group_rules = [
  {
    name           = "allow_nfs_from_eks_nodes"
    description    = "Allow NFS from EKS nodes"
    from_port      = 2049
    to_port        = 2049
    protocol       = "tcp"
    type           = "ingress"
    security_groups = [module.eks.node_security_group_id]
  },
  {
    name           = "allow_all_egress"
    description    = "Allow all outbound traffic"
    from_port      = 0
    to_port        = 0
    protocol       = "-1"
    type           = "egress"
    cidr_blocks    = ["0.0.0.0/0"]
  }
]

efs_performance = "generalPurpose"
efs_throughput = "bursting"
efs_transition_to_ia = "AFTER_30_DAYS"
encrypt_efs = true
efs_creation_token = "efs-for-eks"
efs_csi_driver_name = "aws-efs-csi-driver"
helm_efs_csi_repo = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
helm_efs_csi_charts = "aws-efs-csi-driver"
efs_namespace = "kube-system"
efs_policy_name = "EFS-CSI-POLICY"
efs_role_name = "efs-csi-driver-role"
helm_efs_version = "2.5.7"
storage_class_name = "efs-sc"
provisioning_mode = "efs-ap"
directory_permission = "700"
