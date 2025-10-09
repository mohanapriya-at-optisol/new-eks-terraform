 
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.4.0"
  name = local.vpc_name
  cidr = "10.0.0.0/16"
 
  azs             = ["${var.region_name}a", "${var.region_name}b", "${var.region_name}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  intra_subnets   = ["10.0.201.0/24", "10.0.202.0/24", "10.0.203.0/24"]
 
  enable_nat_gateway = true
  single_nat_gateway = true
  one_nat_gateway_per_az = false
  enable_dns_support   = true
  private_subnet_names = ["${local.vpc_name}-priv-1", "${local.vpc_name}-priv-2", "${local.vpc_name}-priv-3"]
  public_subnet_names  = ["${local.vpc_name}-pub-1", "${local.vpc_name}-pub-2", "${local.vpc_name}-pub-3"]
  intra_subnet_names = ["${local.vpc_name}-intra-1", "${local.vpc_name}-intra-2", "${local.vpc_name}-intra-3"]
 
  private_subnet_tags = {
    Tier                     = "private"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery" = local.cluster_name
  }
 
  public_subnet_tags = {
    Tier = "public"
    "kubernetes.io/role/elb" = "1"
 
  }
}