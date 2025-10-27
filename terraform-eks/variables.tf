variable "environment" {
    type = string
}
variable "region_name" {
    type = string
}
variable "aws_account_id" {
    type = string
}
variable "vpc_cidr" {
    type = string
}
variable "azs"{
    type = list(string)
}
variable "public_subnets_range" {
    type = list(string)
}
variable "private_subnets_range" {
    type = list(string)
}
variable "intra_subnets_range" {
    type = list(string)
}
variable "private_subnet_name"{
  type = string
}
variable "public_subnet_name"{
  type = string
}
variable "intra_subnet_name"{ 
  type = string
}
variable "nat_gateway" {
    type = bool
}
variable "single_nat_gateway" {
    type = bool
}
variable "one_nat_gateway_per_az" {
    type = bool
}
variable "enable_dns_support" {
    type = bool
}
variable "cluster_name"{
    type = string
}
variable "cluster_version"{
    type = string
}
variable "enable_eks_public_access" {
    type = bool
}
variable "enable_eks_private_access" {
    type = bool
}
variable "enable_admin_permissions" {
    type = bool
}
variable "irsa" {
    type = bool
}
variable "kms_alias" {
    type = string
} 
variable "node_group_name"{
    type = string
}
variable "node_instance_type" {
    type = string
}
variable "node_ami_type" {
  type        = string

  validation {
    condition = contains(
      ["AL2_x86_64", "AL2_x86_64_GPU", "AL2_ARM_64", "AL2023_x86_64_STANDARD"],
      var.node_ami_type
    )
    error_message = "node_ami_type must be one of: AL2_x86_64, AL2_x86_64_GPU, AL2_ARM_64, or AL2023_x86_64_STANDARD."
  }
}
variable "min_size" {
    type = number
}
variable "max_size" {
    type = number
}
variable "desired_size" {
    type = number
}
variable "disk_size"{
    type = number
}
variable "instance_profile" {
    type = bool
}

variable "node_iam_role_additional_policies" {
  type        = map(string)
  description = "Additional IAM policies to attach to the Karpenter node IAM role"
}

variable "karpenter_controller_policy_statements" {
  type = list(object({
    Effect   = string
    Action   = list(string)
    Resource = string
  }))
  description = "IAM policy statements for Karpenter controller"
}
variable "helm_create_ns"{
  type = bool
}
variable "karpenter_repo"{
  type = string
}
variable "karpenter_version"{
  type = string
}
variable "helm_chart_name"{
  type  = string
}
variable "karpenter_capacity_types" {
  type = list(string)
}
variable "karpenter_instance_types" {
  type = list(string)
}
variable "karpenter_cpu_limit" {
  type = number
}
variable "karpenter_ttl_seconds_after_empty" {
  type = number
}
variable "karpenter_provisioner_name"{
  type = string
}
variable "karpenter_provider_ref_name"{
  type = string
}
variable "karpenter_node_template_name"{
  type = string
}
variable "tags" {
  type        = map(string)
}
variable "enable_efs_storage"{
type = bool
}

variable "security_group_additional_rules" {
  type = map(object({
    description                = string
    from_port                  = number
    to_port                    = number
    protocol                   = string
    type                       = string
    source_node_security_group = bool
    cidr_blocks                = list(string)
  }))
  description = "Additional security group rules for EKS cluster"
}

variable "node_security_group_additional_rules" {
  description = "Additional security group rules for EKS node security group"
  type = map(object({
    description          = string
    from_port            = number
    to_port              = number
    protocol             = string
    type                 = string
    self                 = bool
    cidr_blocks          = list(string)
  }))
}
variable "efs_sg_name"{
  type = string
}
variable "efs_security_group_rules" {
  description = "Additional security group rules for EFS"
  type = list(object({
    name           = string
    description    = string
    from_port      = number
    to_port        = number
    protocol       = string
    type           = string   # ingress or egress
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
  }))
}


variable "efs_performance"{
  type = string
}
variable "efs_throughput"{
  type = string
}
variable "efs_transition_to_ia"{
  type = string
}
variable "efs_csi_driver_name"{
  type = string
}
variable "helm_efs_csi_repo"{
  type = string

}
variable "helm_efs_csi_charts"{
  type =string
}

variable "efs_creation_token"{
  type = string
}
variable "encrypt_efs"{
  type = bool
}
variable "efs_namespace"{
  type = string
}
variable "efs_policy_name"{
  type = string
}
variable "efs_role_name"{
  type = string
}
variable "helm_efs_version"{
  type = string
}
variable "storage_class_name"{
  type = string
}

variable "provisioning_mode"{
  type = string
}
variable "directory_permission"{
  type = string
}
variable "alb_policy_name"{
  type = string
}
