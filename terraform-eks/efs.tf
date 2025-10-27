# EFS File System for EKS
resource "aws_security_group" "efs" {
  name        = "${local.cluster_name}-${var.efs_sg_name}"
  description = "Security group for EFS mount targets"
  vpc_id      = module.vpc.vpc_id

  tags = {
    Name        = "${local.cluster_name}-efs-sg"
    Environment = var.environment
  }
}
resource "aws_security_group_rule" "efs_rules" {
  for_each = {
    for rule in var.efs_security_group_rules :
    rule.name => rule
  }

  security_group_id = aws_security_group.efs.id
  description        = each.value.description
  type               = each.value.type
  from_port          = each.value.from_port
  to_port            = each.value.to_port
  protocol           = each.value.protocol
  cidr_blocks        = lookup(each.value, "cidr_blocks", [])
  source_security_group_id = (
    length(lookup(each.value, "security_groups", [])) > 0 ?
    each.value.security_groups[0] :
    null
  )
}


# EFS File System
resource "aws_efs_file_system" "eks" {
  creation_token = "${local.cluster_name}-${var.efs_creation_token}"
  encrypted      = var.encrypt_efs

  performance_mode = var.efs_performance
  throughput_mode  = var.efs_throughput

  lifecycle_policy {
    transition_to_ia = var.efs_transition_to_ia
  }

  tags = {
    Name        = "${local.cluster_name}-efs"
    Environment = var.environment
  }
}

# EFS Mount Targets (one per AZ)
resource "aws_efs_mount_target" "eks" {
  count = length(module.vpc.private_subnets)

  file_system_id  = aws_efs_file_system.eks.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}

# IAM Policy for EFS CSI Driver
resource "aws_iam_policy" "efs_csi_driver" {
  name        = "${local.cluster_name}-${var.efs_policy_name}"
  description = "IAM policy for EFS CSI Driver"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeAvailabilityZones"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:CreateAccessPoint"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:RequestTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:TagResource"
        ]
        Resource = "*"
        Condition = {
          StringLike = {
            "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticfilesystem:DeleteAccessPoint"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/efs.csi.aws.com/cluster" = "true"
          }
        }
      }
    ]
  })
}

# IAM Role for EFS CSI Driver
resource "aws_iam_role" "efs_csi_driver" {
  name = "${local.cluster_name}-${var.efs_role_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = module.eks.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:efs-csi-controller-sa"
            "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "efs_csi_driver" {
  policy_arn = aws_iam_policy.efs_csi_driver.arn
  role       = aws_iam_role.efs_csi_driver.name
}

# Install EFS CSI Driver via Helm
resource "helm_release" "efs_csi_driver" {
  name       = "${local.cluster_name}-${var.efs_csi_driver_name}"
  repository = var.helm_efs_csi_repo
  chart      = var.helm_efs_csi_charts
  namespace  = var. efs_namespace
  version    = var.helm_efs_version

  set {
    name  = "controller.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "controller.serviceAccount.name"
    value = "efs-csi-controller-sa"
  }

  set {
    name  = "controller.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.efs_csi_driver.arn
  }

  depends_on = [
    module.eks,
    aws_efs_mount_target.eks
  ]
}

# Kubernetes StorageClass for EFS
resource "kubernetes_storage_class" "efs" {
  metadata {
    name = var.storage_class_name
  }

  storage_provisioner = "efs.csi.aws.com"
  
  parameters = {
    provisioningMode = var.provisioning_mode
    fileSystemId     = aws_efs_file_system.eks.id
    directoryPerms   = var.directory_permission
  }

  depends_on = [helm_release.efs_csi_driver]
}
