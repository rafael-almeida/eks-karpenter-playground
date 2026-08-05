resource "kubernetes_manifest" "ec2_node_class" {
  manifest = yamldecode(templatefile("${path.module}/manifests/ec2-node-class.yaml.tftpl", {
    cluster_name = module.eks.cluster_name
    node_role    = module.karpenter.node_iam_role_name
  }))

  depends_on = [helm_release.karpenter]
}

resource "kubernetes_manifest" "node_pool" {
  manifest = yamldecode(file("${path.module}/manifests/node-pool.yaml"))

  depends_on = [kubernetes_manifest.ec2_node_class]
}
