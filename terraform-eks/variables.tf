variable "environment"{
    type = string
}
variable "region_name"{
    type = string
}
variable "aws_account_id"{
    type = string
}
variable "node_instance_type"{
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
variable "min_mng_size"{
    type = number
}
variable "max_mng_size"{
    type = number
}
variable "desired_mng_size"{
    type = number
}

