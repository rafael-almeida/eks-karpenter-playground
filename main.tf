locals {
  common_tags = merge(var.tags, {
    "karpenter.sh/discovery" = var.cluster_name
  })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  endpoint_public_access                   = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  # Karpenter and the AWS Load Balancer Controller must run somewhere before
  # Karpenter-created capacity exists. Keep this group small and stable.
  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["m7i.large"]

      min_size     = 2
      max_size     = 3
      desired_size = 2

      labels = {
        role = "system"
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.common_tags
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 21.0"

  cluster_name = module.eks.cluster_name

  create_pod_identity_association = true
  enable_spot_termination         = true

  tags = local.common_tags
}

module "load_balancer_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 6.0"

  role_name                              = "${var.cluster_name}-aws-load-balancer-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = local.common_tags
}
