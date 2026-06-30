# Guia de Integração — Cache (FCGLibCache), Kong e Prometheus

## Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Pré-requisitos de Infraestrutura](#2-pré-requisitos-de-infraestrutura)
3. [Integração do Prometheus (Obrigatório para todas as APIs)](#3-integração-do-prometheus-obrigatório-para-todas-as-apis)
4. [Integração da Lib de Cache — FCGLibCache](#4-integração-da-lib-de-cache--fcglibcache)
5. [Implementação por API](#5-implementação-por-api)
6. [Integração com o Kong API Gateway](#6-integração-com-o-kong-api-gateway)
7. [Queries do Prometheus para o Grafana](#7-queries-do-prometheus-para-o-grafana)
8. [Kubernetes Secrets — Referência](#8-kubernetes-secrets--referência)
9. [Checklist de Implementação](#9-checklist-de-implementação)

---

## 1. Visão Geral da Arquitetura

```
                            ┌──────────────────┐
                            │   Kong Gateway   │
        Clientes ──────────►│   porta: 8000    │
                            └────────┬─────────┘
                                     │
            ┌────────────┬───────────┼───────────┬────────────────┐
            │            │           │           │                │
      ┌─────▼───┐  ┌─────▼───┐ ┌────▼────┐ ┌────▼──────────┐ ┌──▼──────────┐
      │UsersAPI │  │CatalogAPI│ │Payments │ │NotificationAPI│ │ Orchestrator│
      │  :80    │  │   :80    │ │ API :80 │ │     :80       │ │    :80      │
      └────┬────┘  └────┬────┘ └────┬────┘ └──────┬────────┘ └──────┬──────┘
           │            │           │              │                 │
      ┌────▼────────────▼───────────▼──────────────▼─────────────────▼────┐
      │                        Redis Cache (6379)                         │
      └──────────────────────────────────────────────────────────────────┘
           │            │           │              │                 │
      ┌────▼────────────▼───────────▼──────────────▼─────────────────▼────┐
      │                     Prometheus (9090) ──► Grafana (3000)          │
      └──────────────────────────────────────────────────────────────────┘
```

---

## 2. Pré-requisitos de Infraestrutura

Todos estes serviços já estão deployados no namespace `fcg-tech-fase-2`:

| Serviço | Service Name (DNS interno) | Porta | Secret |
|---|---|---|---|
| Redis | `redis` | 6379 | `redis-secret` (key: `password`) |
| Prometheus | `prometheus` | 9090 | — |
| Grafana | `grafana` | 3000 | admin/admin |
| Kong Proxy | `kong-proxy` | 80 | — |
| Kong Admin | `kong-admin` | 8001 | — |

### Acesso local (port-forward)

```bash
kubectl port-forward svc/grafana 3000:3000 -n fcg-tech-fase-2
kubectl port-forward svc/prometheus 9090:9090 -n fcg-tech-fase-2
kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2
kubectl port-forward svc/konga 1337:1337 -n fcg-tech-fase-2
```

---

## 3. Integração do Prometheus (Obrigatório para todas as APIs)

> **OBRIGATÓRIO:** Todas as APIs devem expor métricas no endpoint `/metrics` no formato Prometheus.
> O Prometheus já está configurado para fazer scrape de todas as APIs a cada 15 segundos.

### 3.1. Pacote NuGet necessário

```bash
dotnet add package prometheus-net.AspNetCore
```

### 3.2. Configuração no `Program.cs`

```csharp
using Prometheus;

var builder = WebApplication.CreateBuilder(args);

// ... demais serviços ...

var app = builder.Build();

// Métricas HTTP automáticas (request count, duration, in-progress)
app.UseHttpMetrics(options =>
{
    options.AddCustomLabel("app", context => "NOME_DA_API"); // ver tabela abaixo
});

// Endpoint /metrics para o Prometheus coletar
app.MapMetrics();

// ... rotas da aplicação ...
app.Run();
```

**Label `app` por API:**

| API | Valor do label `app` |
|---|---|
| UsersAPI | `users-api` |
| CatalogAPI | `catalog-api` |
| PaymentsAPI | `payments-api` |
| NotificationAPI | `notification-api` |
| Orchestrator | `orchestrator` |

### 3.3. Métricas Customizadas (Recomendado)

Adicionar métricas específicas de negócio para dashboards no Grafana:

```csharp
// filepath: Metrics/AppMetrics.cs
using Prometheus;

namespace SuaAPI.Metrics;

public static class AppMetrics
{
    // ─── Métricas de Cache ─────────────────────────────────
    public static readonly Counter CacheHits = Metrics.CreateCounter(
        "cache_hits_total",
        "Total de cache hits",
        new CounterConfiguration { LabelNames = new[] { "endpoint" } });

    public static readonly Counter CacheMisses = Metrics.CreateCounter(
        "cache_misses_total",
        "Total de cache misses",
        new CounterConfiguration { LabelNames = new[] { "endpoint" } });

    // ─── Métricas de Negócio ───────────────────────────────
    public static readonly Counter OrdersPlaced = Metrics.CreateCounter(
        "orders_placed_total", "Total de pedidos realizados");

    public static readonly Counter PaymentsProcessed = Metrics.CreateCounter(
        "payments_processed_total", "Total de pagamentos processados",
        new CounterConfiguration { LabelNames = new[] { "status" } });

    public static readonly Counter UsersRegistered = Metrics.CreateCounter(
        "users_registered_total", "Total de usuários registrados");

    public static readonly Histogram RequestDuration = Metrics.CreateHistogram(
        "business_request_duration_seconds",
        "Duração de operações de negócio",
        new HistogramConfiguration
        {
            LabelNames = new[] { "operation" },
            Buckets = Histogram.LinearBuckets(0.01, 0.05, 20) // 10ms a 1s
        });
}
```

### 3.4. Uso das Métricas nos Controllers

```csharp
[HttpGet]
public async Task<IActionResult> ListGames()
{
    using (AppMetrics.RequestDuration.WithLabels("list_games").NewTimer())
    {
        var games = await _cache.GetAsync<List<GameDto>>("games:all");
        if (games is not null)
        {
            AppMetrics.CacheHits.WithLabels("GET /games").Inc();
            return Ok(games);
        }

        AppMetrics.CacheMisses.WithLabels("GET /games").Inc();
        games = await _repo.GetAllAsync();
        await _cache.SetAsync("games:all", games, TimeSpan.FromMinutes(5));
        return Ok(games);
    }
}
```

---

## 4. Integração da Lib de Cache — FCGLibCache

### 4.1. Instalar o pacote NuGet

```bash
dotnet add package FCGLibCache
```

### 4.2. Configuração no `Program.cs` (usando Secrets, SEM appsettings)

A connection string do Redis **deve vir de variáveis de ambiente** injetadas pelo Kubernetes via Secrets.

```csharp
using RedisCache.Library.Extensions;

var builder = WebApplication.CreateBuilder(args);

// ─── Redis Cache via Kubernetes Secrets ────────────────────────
var redisHost = Environment.GetEnvironmentVariable("REDIS_HOST") ?? "localhost";
var redisPort = Environment.GetEnvironmentVariable("REDIS_PORT") ?? "6379";
var redisPassword = Environment.GetEnvironmentVariable("REDIS_PASSWORD") ?? "";

var redisConnectionString = string.IsNullOrEmpty(redisPassword)
    ? $"{redisHost}:{redisPort}"
    : $"{redisHost}:{redisPort},password={redisPassword},abortConnect=false";

builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = redisConnectionString;
    options.KeyPrefix = "PREFIXO_DA_API:";  // ver tabela abaixo
    options.DefaultExpirationInMinutes = 30;
    options.Enabled = true;
});
```

**KeyPrefix por API:**

| API | KeyPrefix | Exemplo de chave gerada |
|---|---|---|
| UsersAPI | `users:` | `users:user:f8437ed0-...` |
| CatalogAPI | `catalog:` | `catalog:games:all` |
| PaymentsAPI | `payments:` | `payments:payment:a788fa17-...` |
| NotificationAPI | `notifications:` | `notifications:config:email` |

### 4.3. Variáveis de Ambiente no Deployment YAML

Cada API deve ter estas env vars adicionadas ao seu `deployment.yaml`:

```yaml
env:
  - name: REDIS_HOST
    value: redis
  - name: REDIS_PORT
    value: "6379"
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: redis-secret
        key: password
```

O Secret `redis-secret` já existe no cluster com a senha do Redis.

### 4.4. Interface `ICacheService` — Métodos Disponíveis

```csharp
public interface ICacheService
{
    // Obtém valor do cache (retorna null se não existir)
    Task<T?> GetAsync<T>(string key, CancellationToken ct = default);

    // Armazena valor no cache com TTL opcional
    Task SetAsync<T>(string key, T value, TimeSpan? expiration = null, CancellationToken ct = default);

    // Remove uma chave
    Task RemoveAsync(string key, CancellationToken ct = default);

    // Remove todas as chaves com o prefixo (ex: "games:" remove "games:1", "games:all")
    Task RemoveByPrefixAsync(string prefixPattern, CancellationToken ct = default);

    // Verifica se existe
    Task<bool> ExistsAsync(string key, CancellationToken ct = default);

    // GET or SET — busca do cache; se não existir, executa factory, cacheia e retorna
    Task<T?> GetOrSetAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null, CancellationToken ct = default);
}
```

---

## 5. Implementação por API

### 5.1. Catalog API (Maior benefício de cache)

#### Endpoints que DEVEM usar cache:

| Método | Endpoint | Cache Key | TTL | Impacto |
|---|---|---|---|---|
| `GET` | `/games` | `games:all` | 5 min | 🔴 Crítico — endpoint mais acessado |
| `GET` | `/games/{id}` | `games:{id}` | 15 min | 🔴 Crítico — detalhe de jogo |
| `GET` | `/library` | `library:{userId}` | 5 min | 🔴 Crítico — biblioteca do usuário |
| `GET` | `/library/{gameId}` | `library:{userId}:{gameId}` | 5 min | 🟠 Alto |
| `GET` | `/orders` | `orders:{userId}` | 3 min | 🟠 Alto |
| `GET` | `/orders/{id}` | `orders:detail:{id}` | 30 min | 🟡 Moderado (imutável) |

#### Endpoints que DEVEM invalidar cache:

| Método | Endpoint | Invalidar chaves |
|---|---|---|
| `POST` | `/games` | `games:all` |
| `PUT` | `/games/{id}` | `games:all`, `games:{id}` |
| `DELETE` | `/games/{id}` | `games:all`, `games:{id}` |
| `POST` | `/orders` | `orders:{userId}`, `library:{userId}` |

#### Exemplo completo — GamesController:

```csharp
using RedisCache.Library.Interfaces;
using Prometheus;
using SuaAPI.Metrics;

[ApiController]
[Route("games")]
public class GamesController : ControllerBase
{
    private readonly IGamesRepository _repo;
    private readonly ICacheService _cache;

    public GamesController(IGamesRepository repo, ICacheService cache)
    {
        _repo = repo;
        _cache = cache;
    }

    // ─── GET /games ────────────────────────────────────────────
    [HttpGet]
    public async Task<IActionResult> ListGames()
    {
        var games = await _cache.GetOrSetAsync(
            "games:all",
            async () => await _repo.GetAllAsync(),
            TimeSpan.FromMinutes(5));

        if (games is not null)
            AppMetrics.CacheHits.WithLabels("GET /games").Inc();
        else
            AppMetrics.CacheMisses.WithLabels("GET /games").Inc();

        return Ok(games);
    }

    // ─── GET /games/{id} ───────────────────────────────────────
    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetGame(Guid id)
    {
        var cacheKey = $"games:{id}";
        var game = await _cache.GetOrSetAsync(
            cacheKey,
            async () => await _repo.GetByIdAsync(id),
            TimeSpan.FromMinutes(15));

        if (game is null) return NotFound();
        return Ok(game);
    }

    // ─── POST /games ───────────────────────────────────────────
    [HttpPost]
    public async Task<IActionResult> CreateGame([FromBody] CreateGameDto dto)
    {
        var game = await _repo.CreateAsync(dto);

        // Invalidar lista de jogos
        await _cache.RemoveAsync("games:all");

        return CreatedAtAction(nameof(GetGame), new { id = game.Id }, game);
    }

    // ─── PUT /games/{id} ───────────────────────────────────────
    [HttpPut("{id:guid}")]
    public async Task<IActionResult> UpdateGame(Guid id, [FromBody] UpdateGameDto dto)
    {
        var game = await _repo.UpdateAsync(id, dto);
        if (game is null) return NotFound();

        // Invalidar cache do jogo e da lista
        await _cache.RemoveAsync($"games:{id}");
        await _cache.RemoveAsync("games:all");

        return Ok(game);
    }

    // ─── DELETE /games/{id} ────────────────────────────────────
    [HttpDelete("{id:guid}")]
    public async Task<IActionResult> DeleteGame(Guid id)
    {
        await _repo.DeleteAsync(id);

        // Invalidar cache do jogo e da lista
        await _cache.RemoveAsync($"games:{id}");
        await _cache.RemoveAsync("games:all");

        return NoContent();
    }
}
```

#### Exemplo — OrdersController:

```csharp
[ApiController]
[Route("orders")]
public class OrdersController : ControllerBase
{
    private readonly IOrdersRepository _repo;
    private readonly ICacheService _cache;

    public OrdersController(IOrdersRepository repo, ICacheService cache)
    {
        _repo = repo;
        _cache = cache;
    }

    [HttpGet]
    public async Task<IActionResult> ListOrders()
    {
        var userId = GetCurrentUserId();
        var orders = await _cache.GetOrSetAsync(
            $"orders:{userId}",
            async () => await _repo.GetByUserIdAsync(userId),
            TimeSpan.FromMinutes(3));

        return Ok(orders);
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetOrder(Guid id)
    {
        var order = await _cache.GetOrSetAsync(
            $"orders:detail:{id}",
            async () => await _repo.GetByIdAsync(id),
            TimeSpan.FromMinutes(30));

        if (order is null) return NotFound();
        return Ok(order);
    }

    [HttpPost]
    public async Task<IActionResult> PlaceOrder([FromBody] PlaceOrderDto dto)
    {
        var userId = GetCurrentUserId();
        var order = await _repo.PlaceAsync(userId, dto);

        // Invalidar cache de pedidos e biblioteca do usuário
        await _cache.RemoveAsync($"orders:{userId}");
        await _cache.RemoveByPrefixAsync($"library:{userId}");

        AppMetrics.OrdersPlaced.Inc();
        return Accepted(order);
    }

    private string GetCurrentUserId() =>
        User.FindFirst("sub")?.Value ?? User.FindFirst("id")?.Value ?? "";
}
```

#### Exemplo — LibraryController:

```csharp
[ApiController]
[Route("library")]
public class LibraryController : ControllerBase
{
    private readonly ILibraryRepository _repo;
    private readonly ICacheService _cache;

    public LibraryController(ILibraryRepository repo, ICacheService cache)
    {
        _repo = repo;
        _cache = cache;
    }

    [HttpGet]
    public async Task<IActionResult> GetLibrary()
    {
        var userId = GetCurrentUserId();
        var library = await _cache.GetOrSetAsync(
            $"library:{userId}",
            async () => await _repo.GetByUserIdAsync(userId),
            TimeSpan.FromMinutes(5));

        return Ok(library);
    }

    [HttpGet("{gameId:guid}")]
    public async Task<IActionResult> CheckOwnership(Guid gameId)
    {
        var userId = GetCurrentUserId();
        var owns = await _cache.GetOrSetAsync(
            $"library:{userId}:{gameId}",
            async () => await _repo.UserOwnsGameAsync(userId, gameId),
            TimeSpan.FromMinutes(5));

        return Ok(new { owns });
    }

    private string GetCurrentUserId() =>
        User.FindFirst("sub")?.Value ?? User.FindFirst("id")?.Value ?? "";
}
```

---

### 5.2. Users API

#### Endpoints que DEVEM usar cache:

| Método | Endpoint | Cache Key | TTL | Impacto |
|---|---|---|---|---|
| `GET` | `/api/users/{id}` | `user:{id}` | 10 min | 🟠 Alto — consultado para validação |

#### Endpoints que NÃO devem ter cache:

| Método | Endpoint | Motivo |
|---|---|---|
| `POST` | `/api/users/register` | Escrita — **deve invalidar** cache se aplicável |
| `POST` | `/api/users/login` | Segurança — token único por sessão |

#### Exemplo — UsersController:

```csharp
using RedisCache.Library.Interfaces;

[ApiController]
[Route("api/users")]
public class UsersController : ControllerBase
{
    private readonly IUserRepository _repo;
    private readonly ICacheService _cache;

    public UsersController(IUserRepository repo, ICacheService cache)
    {
        _repo = repo;
        _cache = cache;
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetUser(string id)
    {
        var user = await _cache.GetOrSetAsync(
            $"user:{id}",
            async () => await _repo.GetByIdAsync(id),
            TimeSpan.FromMinutes(10));

        if (user is null) return NotFound();
        return Ok(user);
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] RegisterDto dto)
    {
        var user = await _repo.RegisterAsync(dto);
        AppMetrics.UsersRegistered.Inc();
        return Created($"/api/users/{user.Id}", user);
    }
}
```

---

### 5.3. Payments API

#### Endpoints que podem usar cache:

| Método | Endpoint | Cache Key | TTL | Impacto |
|---|---|---|---|---|
| `GET` | `/api/payments/{id}` | `payment:{id}` | 30 min | 🟡 Moderado (imutável) |

#### Exemplo:

```csharp
[HttpGet("{id}")]
public async Task<IActionResult> GetPayment(string id)
{
    var payment = await _cache.GetOrSetAsync(
        $"payment:{id}",
        async () => await _repo.GetByIdAsync(id),
        TimeSpan.FromMinutes(30)); // Pagamentos são imutáveis

    if (payment is null) return NotFound();
    return Ok(payment);
}
```

Quando um pagamento é processado via evento MassTransit:

```csharp
public class OrderPlacedConsumer : IConsumer<OrderPlacedEvent>
{
    private readonly IPaymentService _service;

    public async Task Consume(ConsumeContext<OrderPlacedEvent> context)
    {
        var result = await _service.ProcessAsync(context.Message);
        AppMetrics.PaymentsProcessed.WithLabels(result.Status).Inc();
    }
}
```

---

### 5.4. Notification API

A Notification API é **event-driven** (consome filas RabbitMQ), então o cache é menos relevante. O foco é no **Prometheus para rastrear eventos processados**.

```csharp
// Métrica para eventos de notificação
public static readonly Counter NotificationsSent = Metrics.CreateCounter(
    "notifications_sent_total",
    "Total de notificações enviadas",
    new CounterConfiguration { LabelNames = new[] { "type" } });

// No consumer de eventos:
NotificationsSent.WithLabels("welcome_email").Inc();
NotificationsSent.WithLabels("payment_confirmation").Inc();
NotificationsSent.WithLabels("order_confirmation").Inc();
```

---

### 5.5. Orchestrator

O Orchestrator é um Worker Service (sem HTTP endpoints de negócio). O foco é no **Prometheus para rastrear eventos orquestrados**.

```csharp
// Métricas para o Orchestrator
public static readonly Counter EventsReceived = Metrics.CreateCounter(
    "orchestrator_events_received_total",
    "Total de eventos recebidos pelo Orchestrator",
    new CounterConfiguration { LabelNames = new[] { "event_type" } });

public static readonly Counter EventsProcessed = Metrics.CreateCounter(
    "orchestrator_events_processed_total",
    "Total de eventos processados com sucesso",
    new CounterConfiguration { LabelNames = new[] { "event_type" } });

public static readonly Counter EventsFailed = Metrics.CreateCounter(
    "orchestrator_events_failed_total",
    "Total de eventos com falha no processamento",
    new CounterConfiguration { LabelNames = new[] { "event_type" } });
```

Uso no handler de eventos:

```csharp
public async Task HandleAsync(OrderPlacedEvent evt)
{
    OrchestratorMetrics.EventsReceived.WithLabels("OrderPlacedEvent").Inc();
    try
    {
        await _logRepository.SaveAsync(/* ... */);
        OrchestratorMetrics.EventsProcessed.WithLabels("OrderPlacedEvent").Inc();
    }
    catch (Exception ex)
    {
        OrchestratorMetrics.EventsFailed.WithLabels("OrderPlacedEvent").Inc();
        throw;
    }
}
```

---

## 6. Integração com o Kong API Gateway

### 6.1. Rotas configuradas no Kong

| Rota | Serviço upstream | Autenticação |
|---|---|---|
| `POST /api/users/login` | `users-api:80` | Pública (sem JWT) |
| `POST /api/users/register` | `users-api:80` | Pública (sem JWT) |
| `/api/users/*` | `users-api:80` | JWT obrigatório |
| `/api/catalog/*` | `catalog-api:80` | JWT obrigatório |
| `/api/products/*` | `catalog-api:80` | JWT obrigatório |

### 6.2. Como as APIs recebem o JWT validado

O Kong valida o JWT **antes** de encaminhar a request para o microserviço. As APIs podem confiar que, se a request chegou, o token é válido.

Para extrair dados do usuário no controller:

```csharp
// O Kong passa o header Authorization original para o upstream
// A API pode decodificar o JWT para extrair claims

private string GetCurrentUserId()
{
    return User.FindFirst("sub")?.Value
        ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value
        ?? User.FindFirst("id")?.Value
        ?? "";
}
```

### 6.3. Credenciais JWT configuradas no Kong

| Campo | Valor |
|---|---|
| Consumer | `app-consumer` |
| Algorithm | `HS256` |
| Key (claim `iss`) | `UsersAPI` |
| Secret | `ChaveSuperSecretaCom32Caracteres!` |

As APIs que emitem tokens JWT (UsersAPI) devem usar exatamente o mesmo `iss` e `secret` configurados no Kong.

---

## 7. Queries do Prometheus para o Grafana

### 7.1. Métricas HTTP (todas as APIs)

#### Taxa de requests por segundo (por API)

```promql
rate(http_requests_received_total[5m])
```

#### Taxa de requests por endpoint

```promql
sum by (endpoint) (rate(http_requests_received_total[5m]))
```

#### Latência média por API (p50)

```promql
histogram_quantile(0.5, rate(http_request_duration_seconds_bucket[5m]))
```

#### Latência P95 por API

```promql
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

#### Latência P99 por API

```promql
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

#### Taxa de erros (5xx) por API

```promql
sum by (job) (rate(http_requests_received_total{code=~"5.."}[5m]))
/
sum by (job) (rate(http_requests_received_total[5m]))
```

#### Requests in-progress

```promql
http_requests_in_progress
```

---

### 7.2. Métricas de Cache (Catalog API, Users API)

#### Cache Hit Rate (%)

```promql
sum(rate(cache_hits_total[5m]))
/
(sum(rate(cache_hits_total[5m])) + sum(rate(cache_misses_total[5m])))
* 100
```

#### Cache Hit Rate por endpoint

```promql
rate(cache_hits_total[5m])
/
(rate(cache_hits_total[5m]) + rate(cache_misses_total[5m]))
* 100
```

#### Cache Hits vs Misses (absoluto)

```promql
# Painel com duas séries:
cache_hits_total
cache_misses_total
```

#### Cache Misses por endpoint (identificar endpoints sem cache)

```promql
topk(10, sum by (endpoint) (rate(cache_misses_total[5m])))
```

---

### 7.3. Métricas de Negócio

#### Pedidos realizados por minuto

```promql
rate(orders_placed_total[5m]) * 60
```

#### Pagamentos processados por status

```promql
sum by (status) (rate(payments_processed_total[5m]))
```

#### Usuários registrados por minuto

```promql
rate(users_registered_total[5m]) * 60
```

#### Notificações enviadas por tipo

```promql
sum by (type) (rate(notifications_sent_total[5m]))
```

---

### 7.4. Métricas do Orchestrator

#### Eventos recebidos por tipo

```promql
sum by (event_type) (rate(orchestrator_events_received_total[5m]))
```

#### Eventos processados vs falhados

```promql
# Painel com duas séries:
sum by (event_type) (rate(orchestrator_events_processed_total[5m]))
sum by (event_type) (rate(orchestrator_events_failed_total[5m]))
```

#### Taxa de sucesso do Orchestrator

```promql
sum(rate(orchestrator_events_processed_total[5m]))
/
sum(rate(orchestrator_events_received_total[5m]))
* 100
```

---

### 7.5. Métricas de Infraestrutura

#### APIs UP/DOWN

```promql
up
```

#### Tempo desde último scrape bem-sucedido

```promql
time() - scrape_samples_scraped
```

---

### 7.6. Dashboard recomendado no Grafana

Criar um dashboard com os seguintes painéis:

| # | Painel | Tipo | Query |
|---|---|---|---|
| 1 | APIs Status (UP/DOWN) | Stat | `up` |
| 2 | Request Rate por API | Time series | `sum by (job) (rate(http_requests_received_total[5m]))` |
| 3 | Latência P95 | Time series | `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))` |
| 4 | Taxa de Erro (%) | Gauge | `sum(rate(http_requests_received_total{code=~"5.."}[5m])) / sum(rate(http_requests_received_total[5m])) * 100` |
| 5 | Cache Hit Rate (%) | Gauge | `sum(rate(cache_hits_total[5m])) / (sum(rate(cache_hits_total[5m])) + sum(rate(cache_misses_total[5m]))) * 100` |
| 6 | Cache Hits vs Misses | Time series | `cache_hits_total` + `cache_misses_total` |
| 7 | Pedidos/min | Stat | `rate(orders_placed_total[5m]) * 60` |
| 8 | Pagamentos por status | Pie chart | `sum by (status) (payments_processed_total)` |
| 9 | Eventos Orchestrator | Time series | `sum by (event_type) (rate(orchestrator_events_received_total[5m]))` |
| 10 | Notificações por tipo | Bar chart | `sum by (type) (notifications_sent_total)` |

---

## 8. Kubernetes Secrets — Referência

### 8.1. Secret do Redis (`redis-secret`)

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: redis-secret
  namespace: fcg-tech-fase-2
type: Opaque
data:
  password: cmVkaXNAMTIz    # redis@123
```

### 8.2. Env vars a adicionar em cada deployment YAML

```yaml
# Adicionar no spec.template.spec.containers[0].env de cada API
env:
  # ... variáveis existentes ...

  # ─── Redis Cache ──────────────────────────────────────
  - name: REDIS_HOST
    value: redis
  - name: REDIS_PORT
    value: "6379"
  - name: REDIS_PASSWORD
    valueFrom:
      secretKeyRef:
        name: redis-secret
        key: password
```

### 8.3. Exemplo completo — `catalog-api-deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog-api
  namespace: fcg-tech-fase-2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: catalog-api
  template:
    metadata:
      labels:
        app: catalog-api
    spec:
      containers:
        - name: catalog-api
          image: davidjmarinho/catalog-api:v2  # Nova versão com cache + prometheus
          ports:
            - containerPort: 80
          env:
            # ... variáveis existentes (DB, RabbitMQ, etc.) ...

            # ─── Redis Cache ────────────────────────────
            - name: REDIS_HOST
              value: redis
            - name: REDIS_PORT
              value: "6379"
            - name: REDIS_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: redis-secret
                  key: password
```

> **Importante:** Nenhum `appsettings.json` ou `ConnectionStrings` deve conter a senha do Redis.
> A senha é injetada exclusivamente via Secret do Kubernetes.

---

## 9. Checklist de Implementação

### Por API — Prometheus (OBRIGATÓRIO):

- [ ] Instalar `prometheus-net.AspNetCore`
- [ ] Adicionar `app.UseHttpMetrics()` no `Program.cs`
- [ ] Adicionar `app.MapMetrics()` no `Program.cs`
- [ ] Criar métricas customizadas de negócio (`AppMetrics.cs`)
- [ ] Verificar que `/metrics` responde no Prometheus (http://localhost:9090/targets)
- [ ] Rebuild da imagem Docker

### Por API — Cache (FCGLibCache):

- [ ] Instalar `FCGLibCache`
- [ ] Configurar `AddRedisCache()` no `Program.cs` usando env vars (não appsettings)
- [ ] Adicionar env vars `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD` no deployment YAML
- [ ] Implementar cache nos endpoints GET de leitura
- [ ] Implementar invalidação nos endpoints POST/PUT/DELETE
- [ ] Verificar dados no Redis via `redis-cli`
- [ ] Rebuild da imagem Docker

### Grafana — Dashboard:

- [ ] Abrir http://localhost:3000 (admin/admin)
- [ ] Verificar que datasource Prometheus está configurado (já provisionado automaticamente)
- [ ] Criar dashboard com os painéis da seção 7.6
- [ ] Importar dashboard da comunidade (opcional): ID `10427` (ASP.NET Core)

### Verificação final:

- [ ] Rodar `bash test-e2e.sh` — todos os passos passam
- [ ] Verificar Prometheus targets: http://localhost:9090/targets — todas as APIs `UP`
- [ ] Verificar cache no Redis: `kubectl exec deployment/redis -n fcg-tech-fase-2 -- sh -c 'redis-cli -a "$REDIS_PASSWORD" KEYS "*"'`
- [ ] Verificar dashboards no Grafana com dados em tempo real

---

## Resumo de Pacotes NuGet por API

| API | `FCGLibCache` | `prometheus-net.AspNetCore` |
|---|---|---|
| UsersAPI | ✅ Instalar | ✅ **Obrigatório** |
| CatalogAPI | ✅ Instalar | ✅ **Obrigatório** |
| PaymentsAPI | ✅ Instalar | ✅ **Obrigatório** |
| NotificationAPI | ⚠️ Opcional | ✅ **Obrigatório** |
| Orchestrator | ⚠️ Opcional | ✅ **Obrigatório** |
