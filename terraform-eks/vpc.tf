 
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "6.4.0"
  name = local.vpc_name
  cidr = var.vpc_cidr
 
  azs             = var.azs
  private_subnets  = var.private_subnets_range
  public_subnets  =  var.public_subnets_range
  intra_subnets   = var.intra_subnets_range
 
  enable_nat_gateway = var.nat_gateway
  single_nat_gateway = var.single_nat_gateway
  one_nat_gateway_per_az = var.one_nat_gateway_per_az
  enable_dns_support   = var.enable_dns_support

  private_subnet_names = [for i in range(length(var.private_subnets_range)) : format("%s-%s-%d", local.vpc_name,var.private_subnet_name, i)]
  public_subnet_names  = [for i in range(length(var.public_subnets_range)): format("%s-%s-%d", local.vpc_name,var.public_subnet_name, i)]
  intra_subnet_names = [for i in range(length(var.intra_subnets_range)): format("%s-%s-%d", local.vpc_name,var.intra_subnet_name, i)]
 
  private_subnet_tags = {
    Tier                     = "private"
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery" = local.cluster_name
    Environment = var.environment
  }
 
  public_subnet_tags = {
    Tier = "public"
    "kubernetes.io/role/elb" = "1"
     Environment = var.environment
  }
}
