# =============================================================================
# CERT-MANAGER - Direct Helm Installation
# =============================================================================
resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.13.2"
  namespace        = "cert-manager"
  create_namespace = true

  set = [
    {
      name  = "installCRDs"
      value = "true"
    }
  ]

  depends_on = [module.retail_app_eks]
}

# =============================================================================
# NGINX INGRESS CONTROLLER - Direct Helm Installation
# =============================================================================
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.8.3"
  namespace        = "ingress-nginx"
  create_namespace = true

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.service.externalTrafficPolicy"
      value = "Local"
    },
    {
      name  = "controller.resources.requests.cpu"
      value = "100m"
    },
    {
      name  = "controller.resources.requests.memory"
      value = "128Mi"
    },
    {
      name  = "controller.resources.limits.cpu"
      value = "200m"
    },
    {
      name  = "controller.resources.limits.memory"
      value = "256Mi"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-scheme"
      value = "internet-facing"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "nlb"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-nlb-target-type"
      value = "instance"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-health-check-path"
      value = "/healthz"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-health-check-port"
      value = "10254"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-health-check-protocol"
      value = "HTTP"
    }
  ]

  depends_on = [module.retail_app_eks]
}