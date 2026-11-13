# Laboratório da Aula 14: observabilidade no seu kind

Sobe no **cluster kind que você já tem na VM Ubuntu** o mesmo cenário da aula:

- **Front da loja instrumentado** com `prom-client` (métricas em `/metrics`) e um **modo caos** para provocar falhas
- **Prometheus, Alertmanager e Grafana** (chart kube-prometheus-stack, via Terraform + Helm)
- **ServiceMonitor** e **PrometheusRule** com os alertas da aula
- **Dashboard pronto** no Grafana e um **receptor de webhook** que imprime as notificações
- **Gerador de carga** para os gráficos terem dados

O lab não recria o cluster e não mexe no seu front. Ele usa o namespace `aula-14` e a porta 30082 (o seu front continua na 30081).

```
lab/
├── .github/workflows/lab-aula-14.yml   pipeline: subir → verificar, caos, derrubar
├── front/        front da loja + src/metricas.js (Counter, Histogram, Gauge)
├── iac/          Terraform: só o helm_release (o cluster já existe)
├── monitoring/   values do chart, webhook de alertas, dashboard do Grafana
├── manifestos/   namespace, Deployment, Service, ServiceMonitor, PrometheusRule, gerador de carga
└── scripts/      subir, verificar, caos, acessar, derrubar (bash, Ubuntu)
```

## 1. Pré-requisitos (na VM)

| Ferramenta | Conferir |
|---|---|
| Cluster kind rodando | `kind get clusters` |
| docker, kind, kubectl | `docker ps`, `kind version`, `kubectl version --client` |
| python3 e curl | `python3 --version` (já vêm no Ubuntu) |
| terraform | opcional: se não houver, o `subir.sh` baixa um para `lab/.bin` |
| Memória livre | ~2 GB a mais (`free -h`) |

## 2. Subir

Escolha **pipeline** (2a) ou **terminal da VM** (2b). Os dois rodam os mesmos scripts.

### 2a. Pelo GitHub Actions (runner self-hosted da VM)

**Onde colocar os arquivos.** O GitHub só lê workflows em `.github/workflows/` na raiz do repositório. Use uma das opções:

- **Opção A (recomendada): no repositório do seu front, que já tem o runner.** Copie a pasta `lab/` inteira para a raiz desse repositório e **mova** o arquivo `lab/.github/workflows/lab-aula-14.yml` para `.github/workflows/lab-aula-14.yml`, ao lado do workflow do seu front.
  ```
  seu-repo/
  ├── .github/workflows/
  │   ├── (workflow do seu front)
  │   └── lab-aula-14.yml      ← movido para cá
  ├── lab/                     ← pasta do lab
  └── (arquivos do seu front)
  ```
- **Opção B: em um repositório novo**, com o **conteúdo** de `lab/` na raiz (o `.github/` já fica no lugar certo). Nesse caso, registre um runner para esse repositório na VM (Settings > Actions > Runners > New self-hosted runner), em outra pasta. Em conta pessoal do GitHub, cada runner atende um repositório só.

O workflow descobre sozinho se o lab está na raiz ou em `lab/`.

**Configuração (opcional)** em Settings > Secrets and variables > Actions:

| Tipo | Nome | Para quê | Padrão |
|---|---|---|---|
| Variable | `KIND_CLUSTER` | nome do cluster kind | o único cluster que existir |
| Secret | `GRAFANA_SENHA` | senha do admin do Grafana | `aula14` |

**Executar.** Faça commit e push na `main`: os jobs **Subir lab** e **Verificar** rodam sozinhos. O Summary da execução mostra as URLs e a tabela de verificação. Pela aba **Actions > Lab Aula 14 > Run workflow**, você escolhe a ação:

| acao | O que faz |
|---|---|
| `subir` | instala/atualiza tudo e verifica |
| `verificar` | só a verificação de ponta a ponta |
| `caos` | roda o **experimento** escolhido (com **valor** opcional) e mostra no Summary os alertas ativos e as últimas notificações |
| `derrubar` | remove o lab |

Para acompanhar um alerta do caos pelo pipeline, rode `caos` com o experimento (ex.: `erro`, valor `0.3`). Espere de 1 a 3 minutos e rode `caos` com `alertas`.

O usuário do runner precisa ter acesso ao Docker. Se o job falhar com `permission denied ... docker.sock`, rode `sudo usermod -aG docker <usuário do runner>` e reinicie o serviço do runner (`sudo ./svc.sh stop && sudo ./svc.sh start` na pasta do runner).

### 2b. Pelo terminal da VM

```bash
cd lab
chmod +x scripts/*.sh          # se o zip perder a permissão
./scripts/subir.sh
```

Com mais de um cluster kind, escolha o cluster: `KIND_CLUSTER=nome ./scripts/subir.sh`. Para trocar a senha do Grafana: `GRAFANA_SENHA=outra ./scripts/subir.sh`.

A primeira execução leva de 5 a 10 minutos (download das imagens). Depois, confira:

```bash
./scripts/verificar.sh         # 11 itens; aguarda até ~3 min pelo primeiro scrape
```

> **Já instalou a observabilidade pelo pipeline da pasta `alunos/`?** O `subir.sh` percebe e **reaproveita** essa instalação: só acrescenta o front do lab, os alertas e o dashboard. A senha do Grafana continua a da sua instalação.

## 3. Acessar

**De dentro da VM** (navegador da VM), pelo IP do nó kind (o `subir.sh` mostra; ou `docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' kind-control-plane`):

| | URL | |
|---|---|---|
| Front | `http://<IP do nó>:30082` | |
| Grafana | `http://<IP do nó>:30300` | admin / aula14, dashboard **Aula 14 - Front da Loja** |
| Prometheus | `http://<IP do nó>:30090` | |
| Alertmanager | `http://<IP do nó>:30903` | |

**De fora da VM** (seu notebook): rode `./scripts/acessar.sh` na VM e deixe aberto. Ele publica as portas 8082 (front), 3000 (Grafana), 9090 (Prometheus) e 9093 (Alertmanager) em `http://IP-DA-VM:porta`. Se não abrir: `sudo ufw allow 8082,3000,9090,9093/tcp`; em VM na nuvem, libere também no security group.

## 4. Explorar métricas e PromQL

1. Veja as métricas cruas: `http://<IP do nó>:30082/metrics`.
2. No Prometheus, em **Status > Targets**, o job `front-aula-14` deve ter 2 alvos UP.
3. Em **Graph**, teste:

```promql
up{job="front-aula-14"}                                              # alvo vivo? (1/0)
http_requests_total{job="front-aula-14"}                             # counter: só sobe
sum by (route) (rate(http_requests_total{job="front-aula-14"}[2m]))  # req/s por rota
sum(rate(http_requests_total{status_code=~"5.."}[2m]))
  / sum(rate(http_requests_total[2m]))                               # taxa de erro
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket[2m])))      # latência p95
loja_estoque_produto                                                 # gauge: valor do momento
job:http_requests_erros:ratio_rate2m                                 # recording rule
```

4. Em **Alerts**, veja as regras (Inactive, Pending, Firing). O `ProdutoEsgotado` já dispara, porque a Caneca Kubernetes está com estoque 0.

## 5. Provocar alertas (caos)

Deixe um terminal mostrando as notificações:

```bash
./scripts/caos.sh notificacoes      # = kubectl logs -n monitoring deploy/alerta-webhook -f
```

Em outro terminal, um experimento por vez. Os alertas têm `for: 1m`: espere de 1 a 3 minutos pelo FIRING.

| Comando | O que acontece | Alerta esperado | Receiver |
|---|---|---|---|
| `./scripts/caos.sh erro 0.3` | 30% das requisições voltam 500 | `FrontTaxaDeErroAlta` (critical) | time-front-critico |
| `./scripts/caos.sh latencia 900` | respostas com ~900 ms | `FrontLatenciaAlta` (warning) | time-front |
| `./scripts/caos.sh desligar` | volta ao normal | os dois acima ficam **RESOLVED** | |
| `./scripts/caos.sh replica` | 1 de 2 réplicas | `FrontReplicaIndisponivel` | time-front |
| `./scripts/caos.sh fora-do-ar` | 0 réplicas | `FrontForaDoAr` (inibe os demais) | time-front-critico |
| `./scripts/caos.sh restaurar` | 2 réplicas, caos desligado | tudo RESOLVED | |
| `./scripts/caos.sh matar-pod` | apaga 1 pod; o Deployment recria | (rápido demais para alertar) | |

Comandos de apoio:

```bash
./scripts/caos.sh alertas    # alertas ativos no Alertmanager (e se estão inibidos)
./scripts/caos.sh status     # estado do caos em cada pod
```

Observe no **Grafana** (painéis de erro e latência), no **Prometheus** (Alerts: Pending, depois Firing) e no **Alertmanager** (agrupamento, roteamento por `equipe` e `severity`, e inibição).

> O modo caos fica na memória de cada pod: um pod recriado volta ao normal. Para provocar o erro de novo, rode o `caos.sh` outra vez.

## 6. Entender o que foi instalado

| Arquivo | Conceito |
|---|---|
| `front/src/metricas.js` | tipos de métrica, labels, cuidado com cardinalidade |
| `manifestos/servicemonitor.yaml` | como o Prometheus descobre o alvo (label `app` + nome da porta) |
| `manifestos/prometheusrule.yaml` | recording rules, alertas, `for`, labels de roteamento |
| `monitoring/values-kube-prometheus-stack.yaml` | rotas, receivers e inibição do Alertmanager |
| `monitoring/gerar_dashboard.py` | dashboard como código (gera o `dashboard-front.yaml`) |

Mudou algo? Rode `./scripts/subir.sh` de novo: ele aplica só o que mudou.

## 7. Remover

```bash
./scripts/derrubar.sh
```

O script remove o namespace `aula-14` e o dashboard. Se a plataforma foi instalada por este lab, ela também é removida; se já existia antes, fica. O cluster kind e o seu front não são tocados.

## Problemas comuns

| Sintoma | Causa / solução |
|---|---|
| `há mais de um cluster kind` | `KIND_CLUSTER=<nome> ./scripts/subir.sh` |
| Pods em `Pending` | falta memória na VM: `kubectl describe pod`, `free -h` |
| Front em `ErrImageNeverPull` / `ErrImagePull` | a imagem não entrou no nó: rode o `subir.sh` de novo (ele tenta `kind load` e, se falhar, importa direto no containerd) |
| `port is already allocated` / NodePort em uso | outra coisa usa 30082/30300/30090/30903: `kubectl get svc -A \| grep 30082` |
| Target DOWN no Prometheus | `kubectl get pods -n aula-14`; o `/metrics` responde? |
| Alerta não chega no webhook | veja a aba Alerts do Prometheus (Firing?) e depois o Alertmanager |
| URL não abre de fora da VM | use `./scripts/acessar.sh` e libere as portas no firewall |
| Workflow não aparece na aba Actions | o arquivo precisa estar em `.github/workflows/` na **raiz** do repositório (seção 2a) |
| Job fica em "Waiting for a runner" | o runner da VM está parado ou registrado em outro repositório (Settings > Actions > Runners) |
| `permission denied ... docker.sock` no job | adicione o usuário do runner ao grupo `docker` (seção 2a) |
