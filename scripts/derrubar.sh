#!/usr/bin/env bash
# Remove o laboratório. O cluster kind e o SEU front continuam lá.
#   ./scripts/derrubar.sh
# Se a plataforma (Prometheus/Grafana) foi instalada por este lab, ela também sai.
# Se já existia antes (ex.: pipeline da pasta alunos/), ela fica.
source "$(dirname "$0")/comum.sh"
usar_cluster

info "Removendo o front do laboratório (namespace $NS)"
kubectl delete namespace "$NS" --ignore-not-found
kubectl delete configmap -n monitoring dashboard-front-aula-14 --ignore-not-found

if [ -s "$TF_STATE_PATH" ]; then
  info "Removendo kube-prometheus-stack instalado pelo lab"
  garantir_terraform
  "$TF" -chdir="$LAB/iac" init -input=false -reconfigure -backend-config="path=$TF_STATE_PATH"
  "$TF" -chdir="$LAB/iac" destroy -input=false -auto-approve \
    -var "kube_context=$KUBE_CONTEXT" -var "grafana_senha=$GRAFANA_SENHA"
  # O Helm não remove o namespace (nem as CRDs, que podem ficar)
  kubectl delete namespace monitoring --ignore-not-found
  rm -f "$TF_STATE_PATH" "$TF_STATE_PATH.backup"
else
  aviso "A plataforma não foi instalada por este lab: mantida no cluster."
fi
info "Laboratório removido."
