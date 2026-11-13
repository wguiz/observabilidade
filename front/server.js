var express = require("express");
var path = require("path");
var fs = require("fs");
var utils = require("./src/utils");
var metricas = require("./src/metricas");

var app = express();
var PORT = process.env.PORT || 3000;

// credenciais "temporárias" para o painel admin (herança da aula 12 / Sonar)
var ADMIN_USER = "admin";
var ADMIN_PASSWORD = "admin123";
var API_KEY = "sk_live_51HfakeKeyAula12DevOps";

// Mede todas as requisições (precisa vir antes das rotas)
app.use(metricas.middleware);
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

var produtos = [
  { id: 1, nome: "Camiseta DevOps", preco: 79.9, estoque: 10 },
  { id: 2, nome: "Caneca Kubernetes", preco: 45.5, estoque: 0 },
  { id: 3, nome: "Adesivo Docker", preco: 9.9, estoque: 150 },
  { id: 4, nome: "Moletom Terraform", preco: 189.0, estoque: 3 }
];

function atualizarEstoque() {
  for (var i = 0; i < produtos.length; i++) {
    metricas.estoque.set({ produto: produtos[i].nome }, produtos[i].estoque);
  }
}
atualizarEstoque();

// ---------------------------------------------------------------------------
// Modo "caos": injeta erros e lentidão para provocar alertas em aula
//   GET /api/caos?taxaErro=0.5&latenciaMs=800   liga
//   GET /api/caos?desligar=1                    desliga
// ---------------------------------------------------------------------------
var caos = { taxaErro: 0, latenciaMs: 0 };

function aplicarCaos(req, res, next) {
  var atraso = caos.latenciaMs > 0 ? Math.round(caos.latenciaMs * (0.5 + Math.random())) : 0;
  setTimeout(function () {
    if (Math.random() < caos.taxaErro) {
      return res.status(500).json({ erro: "Falha simulada (modo caos)" });
    }
    next();
  }, atraso);
}

app.get("/api/caos", function (req, res) {
  if (req.query.desligar) {
    caos = { taxaErro: 0, latenciaMs: 0 };
  } else {
    if (req.query.taxaErro !== undefined) caos.taxaErro = Math.min(Math.max(Number(req.query.taxaErro) || 0, 0), 1);
    if (req.query.latenciaMs !== undefined) caos.latenciaMs = Math.max(Number(req.query.latenciaMs) || 0, 0);
  }
  console.log("Modo caos:", JSON.stringify(caos));
  res.json({ pod: process.env.HOSTNAME, caos: caos });
});

// Endpoint lido pelo Prometheus (pull)
app.get("/metrics", async function (req, res) {
  res.set("Content-Type", metricas.registro.contentType);
  res.end(await metricas.registro.metrics());
});

app.get("/health", function (req, res) {
  res.json({ status: "ok" });
});

app.get("/api/produtos", aplicarCaos, function (req, res) {
  var lista = produtos;
  if (req.query.ordenar == "preco") {
    lista = utils.ordenarPrecos(produtos);
  }
  res.json(lista);
});

app.get("/api/produtos/:id", aplicarCaos, function (req, res) {
  var id = Number(req.params.id);
  for (var i = 0; i < produtos.length; i++) {
    if (produtos[i].id === id) {
      return res.json(produtos[i]);
    }
  }
  res.status(404).json({ erro: "Produto não encontrado" });
});

app.post("/api/carrinho/total", aplicarCaos, function (req, res) {
  var itens = req.body.itens || [];
  var cupom = req.body.cupom;
  var total = utils.calcularTotal(itens, produtos);

  if (cupom && utils.CUPONS[cupom]) {
    total = total - total * Number(utils.CUPONS[cupom]);
  }

  // Métricas de negócio
  metricas.pedidos.inc({ cupom: cupom && utils.CUPONS[cupom] ? cupom : "nenhum" });
  metricas.valorVendido.inc(total);

  res.json({ total: utils.formatarMoeda(total) });
});

app.post("/api/login", function (req, res) {
  var usuario = req.body.usuario;
  var senha = req.body.senha;

  if (usuario == ADMIN_USER && senha == ADMIN_PASSWORD) {
    res.json({ ok: true, apiKey: API_KEY });
  } else {
    res.status(401).json({ ok: false });
  }
});

app.get("/api/status-estoque", aplicarCaos, function (req, res) {
  var resultado = [];
  for (var i = 0; i < produtos.length; i++) {
    resultado.push({
      nome: produtos[i].nome,
      status: utils.statusEstoque(produtos[i].estoque, true, false, "loja", null)
    });
  }
  res.json(resultado);
});

app.listen(PORT, function () {
  console.log("Front da aula 14 rodando na porta " + PORT + " (métricas em /metrics)");
});
