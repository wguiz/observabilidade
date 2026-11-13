#!/usr/bin/env bash
# Provoca (e desfaz) problemas no front do laboratório para ver os alertas
# saírem do Prometheus, passarem pelo Alertmanager e chegarem ao webhook.
#
#   ./scripts/caos.sh erro [taxa]        5xx em uma fração das requisições (padrão 0.3)  -> FrontTaxaDeErroAlta
#   ./scripts/caos.sh latencia [ms]      atraso nas respostas (padrão 900 ms)            -> FrontLatenciaAlta
#   ./scripts/caos.sh desligar           desliga erro e latência                          -> RESOLVED
#   ./scripts/caos.sh replica            escala o front para 1 réplica                    -> FrontReplicaIndisponivel
#   ./scripts/caos.sh fora-do-ar         escala o front para 0 réplicas                   -> FrontForaDoAr (inibe os outros)
#   ./scripts/caos.sh matar-pod          apaga um pod (o Deployment recria: self-healing)
#   ./scripts/caos.sh restaurar          desliga o caos e volta para 2 réplicas
#   ./scripts/caos.sh status             estado do caos em cada pod
#   ./scripts/caos.sh alertas            alertas ativos no Alertmanager
#   ./scripts/caos.sh notificacoes       acompanha o webhook (Ctrl+C para sair)
#
# Os alertas têm "for: 1m": espere de 1 a 3 minutos para ver FIRING.
source "$(dirname "$0")/comum.sh"

uso() { sed -n '5,16p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

# Chama /api/caos em TODAS as réplicas (o Service balancearia entre elas)
caos_nos_pods() {
  local pods
  pods=$(pods_do_front)
  [ -n "$pods" ] || erro "nenhum pod do front rodando. Rode ./scripts/caos.sh restaurar"
  for POD in $pods; do
    printf '%-40s ' "$POD"
    kubectl exec -n "$NS" "$POD" -c front -- wget -qO- "http://localhost:3000/api/caos?$1"
    echo
  done
}

escalar() {
  kubectl scale deploy/"$APP" -n "$NS" --replicas="$1"
  [ "$1" -gt 0 ] && kubectl rollout status deploy/"$APP" -n "$NS" --timeout=120s || true
}

ACAO="${1:-}"
[ -n "$ACAO" ] || uso
usar_cluster

case "$ACAO" in
  erro)
    TAXA="${2:-0.3}"
    info "Erro 5xx em $TAXA das requisições (alerta quando passar de 5% por 1 min)"
    caos_nos_pods "taxaErro=$TAXA" ;;
  latencia)
    MS="${2:-900}"
    info "Latência de ~$MS ms (alerta quando o p95 passar de 500 ms por 1 min)"
    caos_nos_pods "latenciaMs=$MS" ;;
  desligar)
    info "Desligando erro e latência"
    caos_nos_pods "desligar=1" ;;
  replica)
    info "Front com 1 de 2 réplicas"
    escalar 1 ;;
  fora-do-ar)
    info "Front com 0 réplicas"
    escalar 0 ;;
  matar-pod)
    POD=$(pods_do_front | head -1)
    [ -n "$POD" ] || erro "nenhum pod do front rodando"
    info "Apagando $POD; o Deployment cria outro no lugar"
    kubectl delete pod -n "$NS" "$POD" --wait=false
    for _ in 1 2 3; do sleep 4; kubectl get pods -n "$NS" -l "app=$APP"; echo; done ;;
  restaurar)
    info "Voltando ao normal: 2 réplicas e caos desligado"
    escalar 2
    caos_nos_pods "desligar=1" ;;
  status)
    caos_nos_pods "" ;;
  alertas)
    kubectl get --raw "$AM_PROXY/api/v2/alerts?active=true" | python3 -c '
import json, sys
ignorar = ("Watchdog", "InfoInhibitor")
alertas = [a for a in json.load(sys.stdin) if a["labels"].get("alertname") not in ignorar]
if not alertas:
    print("Nenhum alerta ativo (fora o Watchdog).")
for a in sorted(alertas, key=lambda a: a["labels"]["alertname"]):
    l = a["labels"]
    estado = "inibido" if a["status"]["inhibitedBy"] else a["status"]["state"]
    print("%-28s severity=%-9s namespace=%-12s %s" % (l["alertname"], l.get("severity", "-"), l.get("namespace", "-"), estado))
' ;;
  notificacoes)
    kubectl logs -n monitoring deploy/alerta-webhook -f --tail=30 ;;
  *) uso ;;
esac
