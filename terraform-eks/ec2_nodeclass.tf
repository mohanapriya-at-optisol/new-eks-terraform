
resource "kubectl_manifest" "karpenter_provisioner" {
  depends_on = [helm_release.karpenter]

  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1alpha5
    kind: Provisioner
    metadata:
      name: ${var.karpenter_provisioner_name}
    spec:
      requirements:
        - key: "karpenter.sh/capacity-type"
          operator: In
          values: ${jsonencode(var.karpenter_capacity_types)}
        - key: "node.kubernetes.io/instance-type"
          operator: In
          values: ${jsonencode(var.karpenter_instance_types)}
      limits:
        resources:
          cpu: ${var.karpenter_cpu_limit}
      providerRef:
        name: ${var.karpenter_provider_ref_name}
      ttlSecondsAfterEmpty: ${var.karpenter_ttl_seconds_after_empty}
  YAML
}

resource "kubectl_manifest" "karpenter_node_template" {
  depends_on = [helm_release.karpenter]

  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1alpha1
    kind: AWSNodeTemplate
    metadata:
      name: ${var.karpenter_node_template_name}
    spec:
      subnetSelector:
        karpenter.sh/discovery: ${local.cluster_name}
      securityGroupSelector:
        karpenter.sh/discovery: ${local.cluster_name}
      instanceProfile: ${module.eks_karpenter.instance_profile_name}
      tags:
        karpenter.sh/discovery: ${local.cluster_name}
        Environment: ${var.environment}
        Name: ${var.karpenter_node_template_name}
  YAML
}
