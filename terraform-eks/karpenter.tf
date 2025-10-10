 
module "eks_karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.3.1"
  cluster_name = module.eks.cluster_name
  
  
  create_instance_profile = var.instance_profile
  
  
  node_iam_role_additional_policies = var.node_iam_role_additional_policies
  depends_on = [module.eks]
}
resource "kubernetes_namespace" "karpenter_na" {
  metadata {
    name = local.karpenter_namespace
  }
}

 
resource "aws_iam_role" "karpenter_controller_role" {
  name = local.karpenter_controller_role_name
  assume_role_policy = data.aws_iam_policy_document.karpenter_controller_assume_role.json
}
 
data "aws_iam_policy_document" "karpenter_controller_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      values   = ["system:serviceaccount:${local.karpenter_namespace}:${local.karpenter_controller_service_acc}"]
      variable = "${replace(module.eks.cluster_oidc_issuer_url,"https://","")}:sub"
    }
  }
}

# Karpenter controller policy
resource "aws_iam_policy" "karpenter_controller_policy" {
  name = local.karpenter_controller_policy_name
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      for statement in var.karpenter_controller_policy_statements : {
        Effect = statement.Effect
        Action = statement.Action
        Resource = statement.Resource == "NODE_IAM_ROLE_ARN" ? module.eks_karpenter.node_iam_role_arn : statement.Resource == "CLUSTER_ARN" ? module.eks.cluster_arn : statement.Resource == "QUEUE_ARN" ? module.eks_karpenter.queue_arn : statement.Resource
      }
    ]
  })
}
 
resource "aws_iam_role_policy_attachment" "karpenter_controller" {
  role       = aws_iam_role.karpenter_controller_role.name
  policy_arn = aws_iam_policy.karpenter_controller_policy.arn
}

resource "kubernetes_service_account" "karpenter_sa" {
  metadata {
    name      = local.karpenter_controller_service_acc
    namespace = local.karpenter_namespace
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller_role.arn
    }
  }
  depends_on = [module.eks, kubernetes_namespace.karpenter_na]
}
 
 
resource "helm_release" "karpenter" {
  name             = "${var.environment}-karpenter"
  namespace        = local.karpenter_namespace
  create_namespace = false
  repository       = "https://charts.karpenter.sh"
  chart            = "karpenter"
  version          = "0.16.3"
 
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
 
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.karpenter_sa.metadata[0].name
  }
 
  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
 
  set {
    name  = "clusterEndpoint"
    value = module.eks.cluster_endpoint
  }
 
  depends_on = [
    module.eks, 
    kubernetes_namespace.karpenter_na,
    module.eks_karpenter,
    kubernetes_service_account.karpenter_sa
  ]
}