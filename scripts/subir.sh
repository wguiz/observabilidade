#!/usr/bin/env bash
# Sobe o laboratório da Aula 14 no cluster kind que JÁ EXISTE na VM:
#   1. Prometheus + Alertmanager + Grafana (Terraform + Helm)
#   2. Receptor de alertas (webhook) e dashboard do Grafana
#   3. Build da imagem do front instrumentado e carga no kind
#   4. Front, ServiceMonitor, regras de alerta e gerador de carga
# Pode rodar de novo quantas vezes quiser (atualiza o que mudou).
#   ./scripts/subir.sh
source "$(dirname "$0")/comum.sh"
precisa docker python3
usar_cluster
info "Cluster: $KIND_CLUSTER (contexto $KUBE_CONTEXT)"

# ---------------------------------------------------------------------------
info "[1/4] Plataforma de observabilidade (kube-prometheus-stack)"
if plataforma_existe && [ ! -s "$TF_STATE_PATH" ]; then
  # Ex.: já instalada pelo pipeline da pasta alunos/. Reaproveita, não reinstala.
  aviso "kube-prometheus-stack já instalado no cluster por outro meio: reaproveitando."
  aviso "A senha do Grafana é a que você definiu nessa instalação."
  REAPROVEITADA=1
else
  garantir_terraform
  mkdir -p "$(dirname "$TF_STATE_PATH")"
  "$TF" -chdir="$LAB/iac" init -input=false -reconfigure -backend-config="path=$TF_STATE_PATH"
  "$TF" -chdir="$LAB/iac" apply -input=false -auto-approve \
    -var "kube_context=$KUBE_CONTEXT" -var "grafana_senha=$GRAFANA_SENHA"
  REAPROVEITADA=0
fi

# O Prometheus e o Alertmanager são criados pelo Operator logo depois do Helm
for _ in $(seq 1 60); do
  kubectl get pod -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -q . \
    && kubectl get pod -n monitoring -l app.kubernetes.io/name=alertmanager --no-headers 2>/dev/null | grep -q . \
    && break
  sleep 10
done
kubectl wait --for=condition=Ready pod --all -n monitoring --timeout=600s

# ---------------------------------------------------------------------------
info "[2/4] Receptor de alertas e dashboard do Grafana"
if [ "$REAPROVEITADA" = 1 ] && kubectl get svc -n monitoring alerta-webhook >/dev/null 2>&1; then
  echo "alerta-webhook já existe (instalado junto com a plataforma)"
else
  kubectl apply -f "$LAB/monitoring/alerta-webhook.yaml"
fi
kubectl apply -f "$LAB/monitoring/dashboard-front.yaml"

# ---------------------------------------------------------------------------
info "[3/4] Build da imagem $IMAGEM e carga no kind"
docker build -t "$IMAGEM" "$LAB/front"
carregar_imagem

# ---------------------------------------------------------------------------
info "[4/4] Front, ServiceMonitor, regras de alerta e gerador de carga (namespace $NS)"
JA_EXISTIA=0
kubectl get deploy "$APP" -n "$NS" >/dev/null 2>&1 && JA_EXISTIA=1
kubectl apply -f "$LAB/manifestos/00-namespace.yaml"
kubectl apply -f "$LAB/manifestos/"
# Mesma tag com imagem nova: reinicia para os pods usarem a imagem recém-carregada
[ "$JA_EXISTIA" = 1 ] && kubectl rollout restart deploy/"$APP" -n "$NS"
kubectl rollout status deploy/"$APP" -n "$NS" --timeout=180s
kubectl rollout status deploy/gerador-carga -n "$NS" --timeout=180s

IP=$(ip_do_no)
SENHA="$GRAFANA_SENHA"; [ "$REAPROVEITADA" = 1 ] && SENHA="(a da sua instalação)"
echo
info "Pronto! De dentro da VM:"
echo "  Front         http://$IP:30082"
echo "  Grafana       http://$IP:30300   admin / $SENHA   (dashboard: Aula 14 - Front da Loja)"
echo "  Prometheus    http://$IP:30090"
echo "  Alertmanager  http://$IP:30903"
echo
echo "  De fora da VM:      ./scripts/acessar.sh"
echo "  Conferir tudo:      ./scripts/verificar.sh"
echo "  Provocar alertas:   ./scripts/caos.sh"
echo "  Ver notificações:   kubectl logs -n monitoring deploy/alerta-webhook -f"

resumo "## Laboratório da Aula 14 no cluster \`$KIND_CLUSTER\`"
resumo ""
resumo "| | De dentro da VM | De fora da VM (rode \`scripts/acessar.sh\` na VM) |"
resumo "|---|---|---|"
resumo "| Front | http://$IP:30082 | http://IP-DA-VM:8082 |"
resumo "| Grafana (admin / $SENHA) | http://$IP:30300 | http://IP-DA-VM:3000 |"
resumo "| Prometheus | http://$IP:30090 | http://IP-DA-VM:9090 |"
resumo "| Alertmanager | http://$IP:30903 | http://IP-DA-VM:9093 |"
