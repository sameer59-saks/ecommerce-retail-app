# Prometheus Monitoring Stack Deployment Guide

## Overview

This Terraform configuration deploys a comprehensive monitoring stack using the `kube-prometheus-stack` Helm chart, which includes:

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **AlertManager**: Alert routing and management
- **Node Exporter**: Node-level metrics
- **Kube State Metrics**: Kubernetes cluster metrics
- **ServiceMonitors**: Automatic discovery of retail store application metrics

## Components Deployed

### 1. Prometheus Server
- **Retention**: 30 days
- **Storage**: 50Gi persistent volume (GP2)
- **Resources**: 200m CPU, 2Gi RAM (requests) / 1000m CPU, 4Gi RAM (limits)
- **Access**: `http://prometheus.{domain}` or `http://prometheus.localhost`

### 2. Grafana Dashboard
- **Admin Password**: Randomly generated and stored in AWS Secrets Manager
- **Storage**: 10Gi persistent volume for dashboards
- **Pre-configured Dashboards**:
  - Kubernetes Cluster Monitoring (ID: 7249)
  - Kubernetes Pod Monitoring (ID: 6417)
  - NGINX Ingress Controller (ID: 9614)
- **Access**: `http://grafana.{domain}` or `http://grafana.localhost`

### 3. AlertManager
- **Storage**: 10Gi persistent volume
- **Resources**: 100m CPU, 128Mi RAM (requests)
- **Access**: `http://alertmanager.{domain}` or `http://alertmanager.localhost`

### 4. ServiceMonitors
Automatically configured for all retail store services:
- **Cart Service**: `/actuator/prometheus` endpoint
- **Catalog Service**: `/metrics` endpoint (Go application)
- **Checkout Service**: `/actuator/prometheus` endpoint
- **Orders Service**: `/actuator/prometheus` endpoint
- **UI Service**: `/actuator/prometheus` endpoint

## Deployment Steps

### 1. Deploy the Monitoring Stack
```bash
cd terraform
terraform plan -var="enable_monitoring=true"
terraform apply -var="enable_monitoring=true"
```

### 2. Optional: Set Custom Domain
```bash
terraform apply -var="domain_name=your-domain.com"
```

### 3. Access the Services

#### Port Forwarding (if no ingress domain)
```bash
# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80

# Prometheus
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090

# AlertManager
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
```

#### Via Ingress (with domain)
- Grafana: `http://grafana.your-domain.com`
- Prometheus: `http://prometheus.your-domain.com`
- AlertManager: `http://alertmanager.your-domain.com`

## Grafana Login

### Retrieve Admin Password
```bash
# Option 1: From Terraform output
terraform output grafana_admin_password

# Option 2: From AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id retail-store-grafana-admin-password \
  --query SecretString --output text | jq -r '.password'

# Option 3: From Kubernetes secret
kubectl get secret grafana-admin-secret -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

- **Username**: `admin`
- **Password**: Use one of the commands above to retrieve

## Monitoring Your Retail Store

### 1. Application Metrics
Each retail store service exposes metrics:
- **Java Services** (Cart, Checkout, Orders, UI): Spring Boot Actuator metrics at `/actuator/prometheus`
- **Go Service** (Catalog): Native Go metrics at `/metrics`

### 2. Key Metrics to Monitor
- **Request Rate**: HTTP requests per second
- **Response Time**: Request latency percentiles
- **Error Rate**: HTTP 4xx/5xx error rates
- **Resource Usage**: CPU, Memory, Disk usage
- **JVM Metrics**: Heap usage, GC performance (Java services)

### 3. Pre-configured Dashboards
1. **Kubernetes Cluster**: Overall cluster health and resource usage
2. **Pod Monitoring**: Individual pod performance
3. **NGINX Ingress**: Ingress controller metrics and traffic

### 4. Custom Queries
Example Prometheus queries for retail store:
```promql
# Request rate per service
rate(http_requests_total[5m])

# 95th percentile response time
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# Error rate
rate(http_requests_total{status=~"4..|5.."}[5m]) / rate(http_requests_total[5m])

# JVM heap usage
jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}
```

## Troubleshooting

### 1. ServiceMonitor Not Discovering Metrics
```bash
# Check if ServiceMonitor is created
kubectl get servicemonitor -n monitoring

# Check if services have correct labels
kubectl get svc -n retail-store --show-labels

# Check Prometheus targets
# Go to Prometheus UI -> Status -> Targets
```

### 2. Grafana Dashboard Issues
```bash
# Check Grafana logs
kubectl logs -n monitoring deployment/kube-prometheus-stack-grafana

# Get admin password
kubectl get secret grafana-admin-secret -n monitoring \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Regenerate password (if needed)
terraform apply -replace="random_password.grafana_admin_password"
```

### 3. Storage Issues
```bash
# Check PVC status
kubectl get pvc -n monitoring

# Check storage class
kubectl get storageclass
```

## Cost Optimization

### Storage Costs
- **Prometheus**: 50Gi GP2 volume (~$5/month)
- **Grafana**: 10Gi GP2 volume (~$1/month)
- **AlertManager**: 10Gi GP2 volume (~$1/month)

### Compute Costs
- **Total Resources**: ~1.3 CPU cores, ~6.5Gi RAM
- **Estimated Cost**: ~$30-50/month (depending on instance types)

### Optimization Tips
1. Reduce Prometheus retention from 30d to 15d
2. Use smaller storage volumes for non-production
3. Adjust resource requests/limits based on actual usage
4. Use spot instances for monitoring workloads

## Security Considerations

### Production Recommendations
1. **Secure Passwords**: ✅ Already implemented with random password generation
2. **Enable HTTPS**: Configure TLS certificates for ingress
3. **Network Policies**: Restrict access to monitoring namespace
4. **RBAC**: Configure proper service account permissions
5. **Secrets Management**: Use AWS Secrets Manager or similar

### Example: Enable HTTPS
```yaml
# Add to Grafana ingress configuration
tls:
  - secretName: grafana-tls
    hosts:
      - grafana.your-domain.com
```

## Maintenance

### Regular Tasks
1. **Monitor Storage Usage**: Check Prometheus disk usage
2. **Update Dashboards**: Import new community dashboards
3. **Review Alerts**: Configure meaningful alerting rules
4. **Backup Grafana**: Export dashboard configurations

### Upgrade Process
```bash
# Update Helm chart version in addons.tf
# Then apply changes
terraform plan
terraform apply
```

## Password Management

### Security Features
1. **Random Generation**: 16-character password with special characters
2. **AWS Secrets Manager**: Encrypted storage with automatic rotation capability
3. **Kubernetes Secret**: Secure delivery to Grafana pod
4. **No Cleartext**: Password never stored in Terraform state as cleartext
5. **Randomized Keys**: Even the secret key names are randomized for additional security
6. **Opaque Secrets**: Kubernetes secret type prevents accidental exposure

### Password Rotation
```bash
# Rotate Grafana admin password
terraform apply -replace="random_password.grafana_admin_password"

# This will:
# 1. Generate a new random password
# 2. Update AWS Secrets Manager
# 3. Update Kubernetes secret
# 4. Restart Grafana pod automatically
```

### Emergency Access
If you lose access to Grafana:
```bash
# Get current password from AWS Secrets Manager
aws secretsmanager get-secret-value \
  --secret-id retail-store-grafana-admin-password \
  --query SecretString --output text | jq -r '.password'

# Or from Kubernetes (key names are randomized)
kubectl get secret grafana-admin-secret -n monitoring -o yaml
# Look for the key starting with "pass-" and decode it:
kubectl get secret grafana-admin-secret -n monitoring \
  -o jsonpath="{.data.pass-*}" | base64 --decode && echo
```

### Backup Credentials
The admin credentials are stored in multiple secure locations:
1. **AWS Secrets Manager**: `retail-store-grafana-admin-password`
2. **Kubernetes Secret**: `grafana-admin-secret` in `monitoring` namespace
3. **Terraform State**: Password hash only (not cleartext)