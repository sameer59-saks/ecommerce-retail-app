# Minimal Prometheus-only monitoring for resource-constrained environments
resource "helm_release" "prometheus_only" {
  name             = "prometheus"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "25.8.0"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 600

  values = [
    yamlencode({
      # Disable heavy components
      alertmanager = {
        enabled = false
      }
      kubeStateMetrics = {
        enabled = false
      }
      nodeExporter = {
        enabled = false
      }
      pushgateway = {
        enabled = false
      }
      
      # Minimal Prometheus server
      server = {
        enabled = true
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "256Mi"
          }
        }
        persistentVolume = {
          enabled = true
          size = "5Gi"
          storageClass = "gp2"
        }
        retention = "3d"
        service = {
          type = "ClusterIP"
        }
      }
    })
  ]

  depends_on = [
    module.retail_app_eks,
    helm_release.ingress_nginx,
    time_sleep.wait_for_nginx
  ]
}

# Simple Grafana deployment
resource "helm_release" "grafana_minimal" {
  name             = "grafana"
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "grafana"
  version          = "7.0.19"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 300

  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "25m"
          memory = "64Mi"
        }
        limits = {
          cpu    = "50m"
          memory = "128Mi"
        }
      }
      persistence = {
        enabled = true
        size = "1Gi"
        storageClassName = "gp2"
      }
      adminPassword = random_password.grafana_admin_password.result
      service = {
        type = "ClusterIP"
      }
      datasources = {
        "datasources.yaml" = {
          apiVersion = 1
          datasources = [
            {
              name = "Prometheus"
              type = "prometheus"
              url = "http://prometheus-server:80"
              access = "proxy"
              isDefault = true
            }
          ]
        }
      }
    })
  ]

  depends_on = [
    helm_release.prometheus_only,
    random_password.grafana_admin_password
  ]
}