resource "kubernetes_namespace_v1" "environment" {
  for_each = toset(["dev0", "dev1"])

  metadata {
    name = each.key
  }

  depends_on = [module.eks]
}

resource "kubernetes_deployment_v1" "ui" {
  for_each = kubernetes_namespace_v1.environment

  metadata {
    name      = "ui"
    namespace = each.key
    labels = {
      app = "ui"
    }
  }

  spec {
    replicas = 2

    selector {
      match_labels = {
        app = "ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "ui"
        }
      }

      spec {
        container {
          name  = "ui"
          image = "hashicorp/http-echo:1.0"
          args  = ["-listen=:8080", "-text=ui from namespace ${each.key}"]

          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "128Mi"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "ui" {
  for_each = kubernetes_namespace_v1.environment

  metadata {
    name      = "ui"
    namespace = each.key
  }

  spec {
    selector = {
      app = "ui"
    }

    port {
      name        = "http"
      port        = 80
      target_port = "http"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_ingress_v1" "ui" {
  for_each = {
    dev0 = var.dev0_host
    dev1 = var.dev1_host
  }

  metadata {
    name      = "ui"
    namespace = each.key

    annotations = {
      "alb.ingress.kubernetes.io/group.name"         = "shared-ui"
      "alb.ingress.kubernetes.io/group.order"        = each.key == "dev0" ? "10" : "20"
      "alb.ingress.kubernetes.io/scheme"             = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"        = "ip"
      "alb.ingress.kubernetes.io/listen-ports"       = jsonencode([{ HTTP = 80 }])
      "alb.ingress.kubernetes.io/healthcheck-path"   = "/"
      "alb.ingress.kubernetes.io/success-codes"      = "200"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      host = each.value

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.ui[each.key].metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.aws_load_balancer_controller]
}
