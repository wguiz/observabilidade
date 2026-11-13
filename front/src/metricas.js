// Instrumentação da aplicação com prom-client (formato de métricas do Prometheus)
var client = require("prom-client");

var registro = new client.Registry();

// Rótulo fixo em todas as métricas desta aplicação
registro.setDefaultLabels({ app: "front-aula-14" });

// Métricas padrão do processo Node.js: CPU, memória, heap, event loop, GC...
client.collectDefaultMetrics({ register: registro });

// COUNTER: só sobe (ou zera quando o processo reinicia).
// Use com rate()/increase() no PromQL.
var requisicoes = new client.Counter({
  name: "http_requests_total",
  help: "Total de requisições HTTP recebidas",
  labelNames: ["method", "route", "status_code"],
  registers: [registro]
});

// HISTOGRAM: distribui as observações em "baldes" (le = less or equal).
// Permite calcular percentis com histogram_quantile().
var duracao = new client.Histogram({
  name: "http_request_duration_seconds",
  help: "Duração das requisições HTTP em segundos",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [registro]
});

// GAUGE: sobe e desce. Representa um valor "do momento".
var estoque = new client.Gauge({
  name: "loja_estoque_produto",
  help: "Quantidade em estoque de cada produto",
  labelNames: ["produto"],
  registers: [registro]
});

// COUNTER de negócio: pedidos fechados e valor vendido
var pedidos = new client.Counter({
  name: "loja_pedidos_total",
  help: "Total de pedidos (cálculos de carrinho) realizados",
  labelNames: ["cupom"],
  registers: [registro]
});

var valorVendido = new client.Counter({
  name: "loja_valor_vendido_reais_total",
  help: "Soma do valor dos carrinhos calculados, em reais",
  registers: [registro]
});

// Middleware Express: mede toda requisição
function middleware(req, res, next) {
  if (req.path === "/metrics") return next();

  var fimTimer = duracao.startTimer();
  res.on("finish", function () {
    // Usamos o padrão da rota (/api/produtos/:id) e NÃO a URL real
    // (/api/produtos/1, /api/produtos/2...) para evitar explosão de
    // cardinalidade: cada combinação de labels vira uma série nova.
    var rota = req.route
      ? req.baseUrl + req.route.path
      : res.statusCode === 404 ? "nao_encontrada" : "arquivos_estaticos";
    var labels = { method: req.method, route: rota, status_code: String(res.statusCode) };
    requisicoes.inc(labels);
    fimTimer(labels);
  });
  next();
}

module.exports = {
  registro: registro,
  middleware: middleware,
  estoque: estoque,
  pedidos: pedidos,
  valorVendido: valorVendido
};
