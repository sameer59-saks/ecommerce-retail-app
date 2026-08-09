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

# Wait for NGINX Ingress Controller to be ready
resource "time_sleep" "wait_for_nginx" {
  depends_on = [helm_release.ingress_nginx]
  create_duration = "60s"
}

# =============================================================================
# MONITORING STACK SECRETS
# =============================================================================
resource "random_password" "grafana_admin_password" {
  length  = 16
  special = true
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  name                    = "${var.cluster_name}-grafana-admin-password"
  description             = "Grafana admin password for ${var.cluster_name} cluster"
  recovery_window_in_days = 7

  tags = {
    Name        = "${var.cluster_name}-grafana-admin"
    Environment = var.environment
    Component   = "monitoring"
  }
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  secret_id = aws_secretsmanager_secret.grafana_admin.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.grafana_admin_password.result
  })
}

resource "random_id" "secret_keys" {
  byte_length = 8
}

resource "kubernetes_secret_v1" "grafana_admin" {
  metadata {
    name      = "grafana-admin-secret"
    namespace = "monitoring"
  }

  data = {
    "user-${random_id.secret_keys.hex}"     = "admin"
    "pass-${random_id.secret_keys.hex}"     = random_password.grafana_admin_password.result
  }

  type = "Opaque"

  depends_on = [helm_release.kube_prometheus_stack]
}

# =============================================================================
# PROMETHEUS MONITORING STACK
# =============================================================================
resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "55.5.0"
  namespace        = "monitoring"
  create_namespace = true
  timeout          = 900
  wait             = true

  values = [
    yamlencode({
      # Prometheus Configuration - Lightweight
      prometheus = {
        prometheusSpec = {
          retention = "7d"
          storageSpec = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "10Gi"
                  }
                }
              }
            }
          }
          resources = {
            requests = {
              cpu    = "50m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "512Mi"
            }
          }
        }
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled = false
        }
      }

      # Grafana Configuration - Lightweight
      grafana = {
        enabled = true
        admin = {
          existingSecret = "grafana-admin-secret"
          userKey = "user-${random_id.secret_keys.hex}"
          passwordKey = "pass-${random_id.secret_keys.hex}"
        }
        persistence = {
          enabled = true
          storageClassName = "gp2"
          size = "2Gi"
        }
        resources = {
          requests = {
            cpu    = "25m"
            memory = "64Mi"
          }
          limits = {
            cpu    = "100m"
            memory = "128Mi"
          }
        }
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled = false
        }
        # Pre-configured dashboards
        dashboardProviders = {
          "dashboardproviders.yaml" = {
            apiVersion = 1
            providers = [
              {
                name = "default"
                orgId = 1
                folder = ""
                type = "file"
                disableDeletion = false
                editable = true
                options = {
                  path = "/var/lib/grafana/dashboards/default"
                }
              }
            ]
          }
        }
        dashboards = {
          default = {
            "kubernetes-cluster-monitoring" = {
              gnetId = 7249
              revision = 1
              datasource = "Prometheus"
            }
            "kubernetes-pod-monitoring" = {
              gnetId = 6417
              revision = 1
              datasource = "Prometheus"
            }
            "nginx-ingress-controller" = {
              gnetId = 9614
              revision = 1
              datasource = "Prometheus"
            }
          }
        }
      }

      # AlertManager Configuration - Lightweight
      alertmanager = {
        enabled = true
        alertmanagerSpec = {
          storage = {
            volumeClaimTemplate = {
              spec = {
                storageClassName = "gp2"
                accessModes      = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = "2Gi"
                  }
                }
              }
            }
          }
          resources = {
            requests = {
              cpu    = "25m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
        }
        service = {
          type = "ClusterIP"
        }
        ingress = {
          enabled = false
        }
      }

      # Node Exporter Configuration
      nodeExporter = {
        enabled = true
      }

      # Kube State Metrics Configuration
      kubeStateMetrics = {
        enabled = true
      }

      # Default ServiceMonitor configurations
      defaultRules = {
        create = true
        rules = {
          alertmanager = true
          etcd = true
          configReloaders = true
          general = true
          k8s = true
          kubeApiserverAvailability = true
          kubeApiserverBurnrate = true
          kubeApiserverHistogram = true
          kubeApiserverSlos = true
          kubelet = true
          kubeProxy = true
          kubePrometheusGeneral = true
          kubePrometheusNodeRecording = true
          kubernetesApps = true
          kubernetesResources = true
          kubernetesStorage = true
          kubernetesSystem = true
          kubeScheduler = true
          kubeStateMetrics = true
          network = true
          node = true
          nodeExporterAlerting = true
          nodeExporterRecording = true
          prometheus = true
          prometheusOperator = true
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


# =============================================================================
# SERVICE MONITORS FOR RETAIL STORE APPLICATIONS
# =============================================================================
# ServiceMonitors will be created after the Prometheus stack is deployed
# This is handled by a separate apply step to avoid CRD dependency issues
resource "time_sleep" "wait_for_prometheus_crds" {
  depends_on = [helm_release.kube_prometheus_stack]
  create_duration = "30s"
}

resource "kubectl_manifest" "retail_store_service_monitors" {
  for_each = toset(["cart", "catalog", "checkout", "orders", "ui"])
  
  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "retail-store-${each.key}"
      namespace = "monitoring"
      labels = {
        app = "retail-store-${each.key}"
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = each.key == "cart" ? "carts" : each.key
        }
      }
      namespaceSelector = {
        matchNames = ["retail-store"]
      }
      endpoints = [
        {
          port = "http"
          path = each.key == "catalog" ? "/metrics" : "/actuator/prometheus"
          interval = "30s"
        }
      ]
    }
  })

  depends_on = [
    helm_release.kube_prometheus_stack,
    time_sleep.wait_for_prometheus_crds
  ]
}

# =============================================================================
# OUTPUTS FOR MONITORING STACK
# =============================================================================
output "prometheus_url" {
  description = "Prometheus URL"
  value       = "http://prometheus.${var.domain_name != null ? var.domain_name : "localhost"}"
}

output "grafana_url" {
  description = "Grafana URL"
  value       = "http://grafana.${var.domain_name != null ? var.domain_name : "localhost"}"
}

output "grafana_admin_password" {
  description = "Grafana admin password (stored in AWS Secrets Manager)"
  value       = random_password.grafana_admin_password.result
  sensitive   = true
}

output "grafana_admin_secret_arn" {
  description = "AWS Secrets Manager ARN for Grafana admin credentials"
  value       = aws_secretsmanager_secret.grafana_admin.arn
}

output "grafana_admin_username" {
  description = "Grafana admin username"
  value       = "admin"
}

output "alertmanager_url" {
  description = "AlertManager URL"
  value       = "http://alertmanager.${var.domain_name != null ? var.domain_name : "localhost"}"
}