#!/usr/bin/env bash
# Confere o laboratório de ponta a ponta. Aguarda até ~3 min pelo primeiro scrape.
#   ./scripts/verificar.sh
source "$(dirname "$0")/comum.sh"
precisa python3
set +e
usar_cluster
OK=0; FALHAS=0; LINHAS=()

item() { # item <0|1> <texto> [dica]
  if [ "$1" = 1 ]; then echo "  [OK]    $2"; OK=$((OK+1)); LINHAS+=("| ✅ | $2 | |")
  else echo "  [FALHA] $2"; [ -n "${3:-}" ] && echo "          dica: $3"; FALHAS=$((FALHAS+1)); LINHAS+=("| ❌ | $2 | ${3:-} |"); fi
}
sim() { "$@" >/dev/null 2>&1 && echo 1 || echo 0; }
# esperar_series <promql> [mínimo de séries]: repete até ter o mínimo ou estourar ~3 min
esperar_series() { local n=0; for _ in $(seq 1 18); do n=$(promql "$1" | conta_series); [ "$n" -ge "${2:-1}" ] && break; sleep 10; done; echo "$n"; }

echo; echo "Cluster: $KIND_CLUSTER"; echo
echo "Plataforma"
TOTAL=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
RUIM=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | grep -vc Running)
item $([ "$TOTAL" -gt 0 ] && [ "$RUIM" = 0 ] && echo 1 || echo 0) "Pods do namespace monitoring rodando ($TOTAL)" "kubectl get pods -n monitoring"
item $(sim kubectl get svc -n monitoring alerta-webhook) "Receptor alerta-webhook" "rode ./scripts/subir.sh"
item $(sim kubectl get configmap -n monitoring dashboard-front-aula-14) "Dashboard do Grafana (ConfigMap)" "kubectl apply -f monitoring/dashboard-front.yaml"

echo; echo "Front (namespace $NS)"
DISP=$(kubectl get deploy "$APP" -n "$NS" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
item $([ "${DISP:-0}" -ge 2 ] && echo 1 || echo 0) "Deployment $APP com 2 réplicas disponíveis (${DISP:-0})" "./scripts/caos.sh restaurar  ou  kubectl describe pods -n $NS"
item $(sim kubectl get servicemonitor "$APP" -n "$NS") "ServiceMonitor $APP" "kubectl apply -f manifestos/"
item $(sim kubectl get prometheusrule "$APP" -n "$NS") "PrometheusRule $APP" "kubectl apply -f manifestos/"
CARGA=$(kubectl get deploy gerador-carga -n "$NS" -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
item $([ "${CARGA:-0}" -ge 1 ] && echo 1 || echo 0) "Gerador de carga rodando" "kubectl scale deploy/gerador-carga -n $NS --replicas=1"

echo; echo "Prometheus (aguarda até ~3 min)"
ALVOS=$(esperar_series "up{job=\"$APP\"} == 1" 2)
item $([ "$ALVOS" -ge 2 ] && echo 1 || echo 0) "Alvos do job $APP com up = 1 ($ALVOS de 2)" "Prometheus > Status > Targets"
METR=$(esperar_series "rate(http_requests_total{job=\"$APP\"}[2m]) > 0")
item $([ "$METR" -gt 0 ] && echo 1 || echo 0) "Tráfego chegando em http_requests_total" "o gerador de carga está rodando?"
REGRAS=$(kubectl get --raw "$PROM_PROXY/api/v1/rules" 2>/dev/null | grep -o "\"name\":\"$APP\.[a-z]*\"" | wc -l | tr -d ' ')
item $([ "$REGRAS" -ge 2 ] && echo 1 || echo 0) "Grupos de regras carregados ($REGRAS de 2)" "kubectl describe prometheusrule $APP -n $NS"
item $(sim kubectl get --raw "$AM_PROXY/api/v2/status") "Alertmanager respondendo" "kubectl get pods -n monitoring"

echo; echo "Resultado: $OK OK, $FALHAS falha(s)"; echo
resumo "## Verificação: $OK OK, $FALHAS falha(s)"
resumo ""
resumo "| | Item | Dica |"
resumo "|---|---|---|"
for l in "${LINHAS[@]}"; do resumo "$l"; done
[ "$FALHAS" = 0 ]
