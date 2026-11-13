terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }

  # State local FORA da pasta do lab (~/.observabilidade/lab-aula-14.tfstate).
  # O scripts/subir.sh passa o caminho no init:
  #   terraform init -backend-config="path=$HOME/.observabilidade/lab-aula-14.tfstate"
  backend "local" {}
}

# O cluster kind JÁ EXISTE: o Terraform só instala o chart nele,
# usando o kubeconfig gerado por "kind export kubeconfig".
provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = var.kube_context
  }
}
