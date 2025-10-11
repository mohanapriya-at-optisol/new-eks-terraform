
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
  kms_key_aliases = ["${local.cluster_name}-kms-alias-version2"]
  
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
      })
    }
  }
   security_group_tags = merge(var.tags, {
    "karpenter.sh/discovery" = local.cluster_name
    Name = "${var.cluster_name}-cluster-sg"
  })
   security_group_additional_rules = {
    ingress_nodes_ephemeral_ports_tcp = {
      description                = "Nodes on ephemeral ports"
      protocol                   = "tcp"
      from_port                  = 1025
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }
   node_security_group_tags = merge(var.tags, {
    "karpenter.sh/discovery" = local.cluster_name
    Name = "${var.cluster_name}-node-sg"
  })
 
  node_security_group_additional_rules = {
    # Allow all traffic between nodes for services like CoreDNS and cross-pod communication
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }
 
 
}
