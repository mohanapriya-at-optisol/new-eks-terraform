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
variable "tags" {
  type        = map(string)
}
variable "enable_efs_storage"{
type = bool
}



