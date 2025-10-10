 
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.4.0"
  name = local.vpc_name
  cidr = "10.0.0.0/16"
 
  azs             = ["${var.region_name}a", "${var.region_name}b", "${var.region_name}c"]
  private_subnets  = var.private_subnets_range
  public_subnets  =  var.public_subnets_range
  intra_subnets   = var.intra_subnets_range
 
  enable_nat_gateway = var.nat_gateway
  single_nat_gateway = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az
  enable_dns_support   = var.enable_dns_support
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