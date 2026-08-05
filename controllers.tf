resource "helm_release" "karpenter" {
  name                = "karpenter"
  namespace           = "kube-system"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = "1.14.0"
  repository_username = data.aws_ecrpublic_authorization_token.token.user_name
  repository_password = data.aws_ecrpublic_authorization_token.token.password

  wait    = true
  timeout = 900

  values = [yamlencode({
    settings = {
      clusterName       = module.eks.cluster_name
      interruptionQueue = module.karpenter.queue_name
    }
    serviceAccount = {
      name = "karpenter"
    }
    controller = {
      resources = {
        requests = {
          cpu    = "500m"
          memory = "512Mi"
        }
        limits = {
          memory = "1Gi"
        }
      }
    }
  })]

  depends_on = [module.eks, module.karpenter]
}

data "aws_ecrpublic_authorization_token" "token" {
  provider = aws.us_east_1
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "kubernetes_service_account_v1" "aws_load_balancer_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    annotations = {
      "eks.amazonaws.com/role-arn" = module.load_balancer_controller_irsa.iam_role_arn
    }
  }

  depends_on = [module.eks]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  namespace  = "kube-system"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.14.0"

  wait    = true
  timeout = 900

  values = [yamlencode({
    clusterName = module.eks.cluster_name
    region      = var.aws_region
    vpcId       = var.vpc_id
    serviceAccount = {
      create = false
      name   = kubernetes_service_account_v1.aws_load_balancer_controller.metadata[0].name
    }
  })]

  depends_on = [kubernetes_service_account_v1.aws_load_balancer_controller]
}
