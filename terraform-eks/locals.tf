locals {
  cluster_name = "${var.environment}-cluster"
  vpc_name     = "${var.environment}-vpc"
  karpenter_namespace = "${var.environment}-karpenter-namespace"
  karpenter_controller_role_name = "${var.environment}-kc-role"
  karpenter_controller_policy_name = "${var.environment}-kc-policy"
  karpenter_controller_service_acc = "${var.environment}-kc-sa"
  
}
