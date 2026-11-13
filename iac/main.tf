# Prometheus Operator + Prometheus + Alertmanager + Grafana
# + node-exporter + kube-state-metrics em um único chart,
# instalados no cluster kind que você JÁ tem (não cria cluster).
resource "helm_release" "kube_prometheus_stack" {
  name             = "monitoring"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = var.kube_prometheus_stack_version
  namespace        = "monitoring"
  create_namespace = true

  timeout = 900
  wait    = true

  values = [file("${path.module}/../monitoring/values-kube-prometheus-stack.yaml")]

  set_sensitive {
    name  = "grafana.adminPassword"
    value = var.grafana_senha
  }
}
