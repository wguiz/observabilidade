#!/usr/bin/env bash
# Configuração e funções compartilhadas pelos scripts do laboratório.
# Tudo pode ser sobrescrito por variável de ambiente, ex.:
#   KIND_CLUSTER=meu-cluster ./scripts/subir.sh
set -euo pipefail

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

NS="aula-14"                       # namespace do front do laboratório
APP="front-aula-14"                # nome do Deployment/Service e job no Prometheus
IMAGEM="front-aula-14:1.0.0"
GRAFANA_SENHA="${GRAFANA_SENHA:-aula14}"
TF_STATE_PATH="${TF_STATE_PATH:-$HOME/.observabilidade/lab-aula-14.tfstate}"
TERRAFORM_VERSAO="1.9.8"           # baixada para lab/.bin se não houver terraform no PATH

PROM_PROXY="/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-prometheus:9090/proxy"
AM_PROXY="/api/v1/namespaces/monitoring/services/monitoring-kube-prometheus-alertmanager:9093/proxy"

info()  { echo -e "\033[1;36m==> $*\033[0m"; }
aviso() { echo -e "\033[1;33m[aviso] $*\033[0m"; [ -n "${GITHUB_ACTIONS:-}" ] && echo "::warning::$*" || true; }
erro()  { echo -e "\033[1;31m[erro] $*\033[0m" >&2; [ -n "${GITHUB_ACTIONS:-}" ] && echo "::error::$*" || true; exit 1; }
# Escreve no Summary do job do GitHub Actions (fora do Actions não faz nada)
resumo() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$*" >> "$GITHUB_STEP_SUMMARY"; fi; }

precisa() { for c in "$@"; do command -v "$c" >/dev/null || erro "'$c' não encontrado no PATH"; done; }

# Descobre o cluster kind (se só existir um, usa ele) e seleciona o contexto
usar_cluster() {
  precisa kind kubectl
  if [ -z "${KIND_CLUSTER:-}" ]; then
    local lista n
    lista=$(kind get clusters 2>/dev/null || true)
    n=$(echo "$lista" | grep -c . || true)
    [ "$n" = 0 ] && erro "nenhum cluster kind encontrado (kind get clusters). Este lab usa o cluster que você já tem."
    [ "$n" -gt 1 ] && erro "há mais de um cluster kind: $(echo $lista). Escolha com: KIND_CLUSTER=<nome> $0"
    KIND_CLUSTER="$lista"
  fi
  kind get clusters | grep -qx "$KIND_CLUSTER" || erro "cluster kind '$KIND_CLUSTER' não existe (kind get clusters)"
  KUBE_CONTEXT="kind-$KIND_CLUSTER"
  kind export kubeconfig --name "$KIND_CLUSTER" >/dev/null 2>&1
  kubectl config use-context "$KUBE_CONTEXT" >/dev/null
}

# IP do nó kind: de dentro da VM os NodePorts respondem nele
ip_do_no() {
  kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}'
}

# Usa o terraform do PATH ou baixa um para lab/.bin (sem sudo)
garantir_terraform() {
  if command -v terraform >/dev/null; then TF=terraform; return; fi
  TF="$LAB/.bin/terraform"
  [ -x "$TF" ] && return
  precisa curl python3
  local arq
  case "$(uname -m)" in x86_64) arq=amd64 ;; aarch64|arm64) arq=arm64 ;; *) erro "arquitetura $(uname -m) não suportada" ;; esac
  info "terraform não encontrado: baixando a versão $TERRAFORM_VERSAO para lab/.bin"
  mkdir -p "$LAB/.bin"
  curl -fsSL -o "$LAB/.bin/tf.zip" \
    "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSAO}/terraform_${TERRAFORM_VERSAO}_linux_${arq}.zip"
  python3 -c 'import sys,zipfile; zipfile.ZipFile(sys.argv[1]).extract("terraform", sys.argv[2])' "$LAB/.bin/tf.zip" "$LAB/.bin"
  rm -f "$LAB/.bin/tf.zip"; chmod +x "$TF"
}

# Plataforma de observabilidade já existe no cluster? (release Helm "monitoring")
plataforma_existe() {
  kubectl get secret -n monitoring -l owner=helm,name=monitoring --no-headers 2>/dev/null | grep -q .
}

# Copia a imagem do Docker da VM para dentro dos nós do kind.
# Se o "kind load" falhar (kind CLI mais velho que o nó), importa direto no containerd.
carregar_imagem() {
  if kind load docker-image "$IMAGEM" --name "$KIND_CLUSTER"; then return; fi
  aviso "kind load falhou; importando a imagem direto no containerd de cada nó"
  for NO in $(kind get nodes --name "$KIND_CLUSTER"); do
    docker save "$IMAGEM" | docker exec -i "$NO" ctr --namespace=k8s.io images import --all-platforms -
  done
}

# Consulta PromQL pelo proxy da API do Kubernetes (sem port-forward)
promql() {
  local q
  q=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$1")
  kubectl get --raw "${PROM_PROXY}/api/v1/query?query=${q}" 2>/dev/null || echo '{}'
}
conta_series() { grep -o '"metric"' | wc -l | tr -d ' '; }

# Pods do front (um por linha)
pods_do_front() {
  kubectl get pods -n "$NS" -l "app=$APP" --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}'
}
