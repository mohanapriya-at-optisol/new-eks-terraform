
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.3.1"
  
  name               = var.cluster_name
  kubernetes_version = var.cluster_version
  endpoint_public_access = var.enable_eks_public_access
  endpoint_private_access = var.enable_eks_private_access
  enable_cluster_creator_admin_permissions = var.enable_admin_permissions

  addons = {
    coredns                = {}
    eks-pod-identity-agent = {
      before_compute = true
    }
    kube-proxy             = {}
    vpc-cni                = {
      before_compute = true
    }
  }
 
  vpc_id = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets
  
  enable_irsa = var.irsa
  
  # Custom KMS key alias to avoid conflicts
  kms_key_aliases = ["${local.cluster_name}-${var.kms_alias}"]
  
  # Apply tags to EKS cluster
  tags = var.tags
  
  #EKS MANAGED NODE GROUP
  eks_managed_node_groups = {
    "${var.node_group_name}" = {
      ami_type       = var.node_ami_type
      instance_types = [var.node_instance_type]
 
      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size
      
      disk_size = var.disk_size  # Uses 50GB from your tfvars
      
      # Apply tags to managed node group
      tags = merge(var.tags, {
        Name = "${var.cluster_name}-mng-nodes"
        "k8s.io/cluster-autoscaler/node-template/label/karpenter.sh/discovery" = local.cluster_name
        Environment = var.environment
      })
    }
  }
   security_group_tags = merge(var.tags, {
    "karpenter.sh/discovery" = local.cluster_name
    Name = "${var.cluster_name}-cluster-sg"
    Environment = var.environment
  })
   security_group_additional_rules = {
  for rule in var.security_group_additional_rules :
  rule.name => {
    description                = rule.description
    from_port                  = rule.from_port
    to_port                    = rule.to_port
    protocol                   = rule.protocol
    type                       = rule.type
    source_node_security_group = rule.source_node_security_group
    cidr_blocks                = rule.cidr_blocks
  }
}

   node_security_group_tags = merge(var.tags, {
    "karpenter.sh/discovery" = local.cluster_name
    Name = "${var.cluster_name}-node-sg"
    Environment = var.environment
  })
 node_security_group_additional_rules = {
  for rule in var.node_security_group_additional_rules :
  rule.name => {
    description          = rule.description
    from_port            = rule.from_port
    to_port              = rule.to_port
    protocol             = rule.protocol
    type                 = rule.type
    self                 = rule.self
    cidr_blocks          = rule.cidr_blocks
  }
}

 
 
}
