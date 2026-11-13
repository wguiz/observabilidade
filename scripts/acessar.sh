#!/usr/bin/env bash
# Publica o front e as ferramentas nas portas da VM, para acessar de FORA
# dela (do seu notebook). Rode na VM e deixe aberto; Ctrl+C encerra.
#
# De DENTRO da VM não precisa: use http://<IP do nó kind>:30082 / 30300 / 30090 / 30903
source "$(dirname "$0")/comum.sh"
usar_cluster

trap 'kill $(jobs -p) 2>/dev/null; echo; echo "Port-forwards encerrados."' EXIT
# Reabre o port-forward se ele cair (ex.: pod recriado pelo caos.sh)
encaminhar() { while true; do kubectl port-forward --address 0.0.0.0 -n "$1" "$2" "$3" >/dev/null 2>&1; sleep 2; done; }
encaminhar "$NS"       svc/"$APP"                                 8082:80 &
encaminhar monitoring  svc/monitoring-grafana                     3000:80 &
encaminhar monitoring  svc/monitoring-kube-prometheus-prometheus  9090:9090 &
encaminhar monitoring  svc/monitoring-kube-prometheus-alertmanager 9093:9093 &

VM_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
echo
echo "Front         http://${VM_IP:-IP-DA-VM}:8082"
echo "Grafana       http://${VM_IP:-IP-DA-VM}:3000   (admin / $GRAFANA_SENHA)"
echo "Prometheus    http://${VM_IP:-IP-DA-VM}:9090"
echo "Alertmanager  http://${VM_IP:-IP-DA-VM}:9093"
echo
echo "Se não abrir, libere as portas no firewall da VM (sudo ufw allow 8082,3000,9090,9093/tcp)"
echo "ou, em VM na nuvem, no security group. Ctrl+C para encerrar..."
wait
