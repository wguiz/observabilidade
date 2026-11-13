variable "kube_context" {
  description = "Contexto do kubeconfig do cluster kind (kind-<nome do cluster>)"
  type        = string
  default     = "kind-kind"
}

variable "kubeconfig_path" {
  description = "Caminho do kubeconfig"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_prometheus_stack_version" {
  description = "Versão do chart prometheus-community/kube-prometheus-stack"
  type        = string
  default     = "93.2.2"
}

variable "grafana_senha" {
  description = "Senha do usuário admin do Grafana"
  type        = string
  default     = "aula14"
  sensitive   = true
}
