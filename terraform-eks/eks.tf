
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.3.1"
  
  name               = local.cluster_name
  kubernetes_version = "1.31"
  endpoint_public_access = true
  endpoint_private_access = true
  enable_cluster_creator_admin_permissions = true
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
  
  enable_irsa = true
  
  # Custom KMS key alias to avoid conflicts
  kms_key_aliases = ["${local.cluster_name}-kms-alias"]
  
  #EKS MANAGED NODE GROUP
  eks_managed_node_groups = {
    karpenter-mng-example = {
      ami_type       = var.node_ami_type
      instance_types = [var.node_instance_type]
 
      min_size     = var.min_mng_size
      max_size     = var.max_mng_size
      desired_size = var.desired_mng_size
    }
  }
   security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name 
  }
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
   node_security_group_tags = {
    "karpenter.sh/discovery" = local.cluster_name
  }
 
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