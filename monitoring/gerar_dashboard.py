"""Gera monitoring/dashboard-front.yaml (ConfigMap com o dashboard do Grafana).

O sidecar do Grafana carrega automaticamente qualquer ConfigMap com o
label grafana_dashboard: "1". Rode:  python monitoring/gerar_dashboard.py
"""
import json
from pathlib import Path

DS = {"type": "prometheus", "uid": "prometheus"}
JOB = 'job="front-aula-14"'
POD = 'namespace="aula-14", pod=~"front-aula-14-.*", container="front"'

_id = 0


def painel(tipo, titulo, x, y, w, h, alvos, unidade="short", descricao="", extra=None):
    global _id
    _id += 1
    p = {
        "id": _id,
        "type": tipo,
        "title": titulo,
        "description": descricao,
        "datasource": DS,
        "gridPos": {"x": x, "y": y, "w": w, "h": h},
        "targets": [
            {"refId": chr(65 + i), "datasource": DS, "expr": expr, "legendFormat": legenda}
            for i, (expr, legenda) in enumerate(alvos)
        ],
        "fieldConfig": {"defaults": {"unit": unidade}, "overrides": []},
        "options": {},
    }
    if tipo == "timeseries":
        p["fieldConfig"]["defaults"]["custom"] = {"lineWidth": 2, "fillOpacity": 10, "showPoints": "never"}
        p["options"] = {"legend": {"displayMode": "list", "placement": "bottom"}, "tooltip": {"mode": "multi"}}
    if extra:
        for k, v in extra.items():
            if k == "defaults":
                p["fieldConfig"]["defaults"].update(v)
            else:
                p[k] = v
    return p


def limites(*passos):
    return {"thresholds": {"mode": "absolute", "steps": [{"color": c, "value": v} for c, v in passos]}}


paineis = [
    {"id": 100, "type": "row", "title": "Golden Signals (RED)", "gridPos": {"x": 0, "y": 0, "w": 24, "h": 1}, "collapsed": False, "panels": []},
    painel("stat", "Requisições/s", 0, 1, 5, 4,
           [(f"sum(rate(http_requests_total{{{JOB}}}[2m]))", "req/s")], "reqps",
           "Rate (tráfego): sum(rate(http_requests_total[2m]))",
           {"defaults": limites(("blue", None))}),
    painel("stat", "Taxa de erro (5xx)", 5, 1, 5, 4,
           [(f'sum(rate(http_requests_total{{{JOB}, status_code=~"5.."}}[2m])) / sum(rate(http_requests_total{{{JOB}}}[2m]))', "erro")],
           "percentunit", "Errors: fração das requisições com status 5xx",
           {"defaults": limites(("green", None), ("orange", 0.01), ("red", 0.05))}),
    painel("stat", "Latência p95", 10, 1, 5, 4,
           [(f"histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket{{{JOB}}}[2m])))", "p95")],
           "s", "Duration: 95% das requisições foram mais rápidas que este valor",
           {"defaults": limites(("green", None), ("orange", 0.25), ("red", 0.5))}),
    painel("stat", "Réplicas no ar", 15, 1, 4, 4,
           [(f"sum(up{{{JOB}}})", "up")], "none", "Quantos alvos o Prometheus conseguiu raspar (métrica up)",
           {"defaults": limites(("red", None), ("orange", 1), ("green", 2))}),
    painel("stat", "Vendido na última hora", 19, 1, 5, 4,
           [(f"sum(increase(loja_valor_vendido_reais_total{{{JOB}}}[1h]))", "R$")], "currencyBRL",
           "Métrica de negócio: increase() de um counter",
           {"defaults": limites(("purple", None))}),

    painel("timeseries", "Requisições/s por rota", 0, 5, 12, 8,
           [(f"sum by (route) (rate(http_requests_total{{{JOB}}}[2m]))", "{{route}}")], "reqps",
           "sum by (route) (rate(http_requests_total[2m]))"),
    painel("timeseries", "Requisições/s por status HTTP", 12, 5, 12, 8,
           [(f"sum by (status_code) (rate(http_requests_total{{{JOB}}}[2m]))", "{{status_code}}")], "reqps",
           "sum by (status_code) (rate(http_requests_total[2m]))"),

    painel("timeseries", "Latência (percentis)", 0, 13, 12, 8,
           [(f"histogram_quantile({q}, sum by (le) (rate(http_request_duration_seconds_bucket{{{JOB}}}[2m])))", f"p{int(q*100)}")
            for q in (0.5, 0.95, 0.99)], "s", "histogram_quantile() sobre os buckets do histograma"),
    painel("timeseries", "Latência média por rota", 12, 13, 12, 8,
           [(f"sum by (route) (rate(http_request_duration_seconds_sum{{{JOB}}}[2m])) / sum by (route) (rate(http_request_duration_seconds_count{{{JOB}}}[2m]))", "{{route}}")],
           "s", "_sum / _count = média"),

    {"id": 101, "type": "row", "title": "Saturação (recursos dos pods)", "gridPos": {"x": 0, "y": 21, "w": 24, "h": 1}, "collapsed": False, "panels": []},
    painel("timeseries", "CPU por pod", 0, 22, 12, 8,
           [(f"sum by (pod) (rate(container_cpu_usage_seconds_total{{{POD}}}[2m]))", "{{pod}}")], "cores",
           "cAdvisor (kubelet): container_cpu_usage_seconds_total"),
    painel("timeseries", "Memória por pod", 12, 22, 12, 8,
           [(f"sum by (pod) (container_memory_working_set_bytes{{{POD}}})", "{{pod}}")], "bytes",
           "cAdvisor (kubelet): container_memory_working_set_bytes"),

    {"id": 102, "type": "row", "title": "Negócio", "gridPos": {"x": 0, "y": 30, "w": 24, "h": 1}, "collapsed": False, "panels": []},
    painel("bargauge", "Estoque por produto (gauge)", 0, 31, 12, 8,
           [("max by (produto) (loja_estoque_produto)", "{{produto}}")], "none",
           "Métrica do tipo gauge: valor atual",
           {"defaults": {**limites(("red", None), ("orange", 1), ("green", 5)), "min": 0},
            "options": {"orientation": "horizontal", "displayMode": "gradient", "showUnfilled": True,
                        "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False}}}),
    painel("timeseries", "Pedidos por minuto por cupom", 12, 31, 12, 8,
           [(f"sum by (cupom) (rate(loja_pedidos_total{{{JOB}}}[2m])) * 60", "{{cupom}}")], "short",
           "rate() * 60 = por minuto"),
]

dashboard = {
    "uid": "front-aula-14",
    "title": "Aula 14 - Front da Loja",
    "tags": ["aula-14", "devops"],
    "timezone": "browser",
    "schemaVersion": 39,
    "version": 1,
    "refresh": "10s",
    "time": {"from": "now-15m", "to": "now"},
    "editable": True,
    "panels": paineis,
    "templating": {"list": []},
    "annotations": {"list": []},
}

corpo = json.dumps(dashboard, indent=2, ensure_ascii=False)
yaml = (
    "# Gerado por monitoring/gerar_dashboard.py - não edite à mão\n"
    "apiVersion: v1\n"
    "kind: ConfigMap\n"
    "metadata:\n"
    "  name: dashboard-front-aula-14\n"
    "  namespace: monitoring\n"
    "  labels:\n"
    '    grafana_dashboard: "1"\n'
    "data:\n"
    "  front-aula-14.json: |\n"
    + "\n".join("    " + linha for linha in corpo.splitlines())
    + "\n"
)
destino = Path(__file__).with_name("dashboard-front.yaml")
destino.write_text(yaml, encoding="utf-8", newline=chr(10))
print(f"Gerado {destino}")
