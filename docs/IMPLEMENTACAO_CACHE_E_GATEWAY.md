# Implementação da Camada de Cache com Redis e API Gateway Kong

## Índice

1. [Contexto e Escopo](#1-contexto-e-escopo)
2. [Pré-requisitos](#2-pré-requisitos)
3. [Infraestrutura com Docker Compose](#3-infraestrutura-com-docker-compose)
4. [Instalação da Biblioteca de Cache nas APIs](#4-instalação-da-biblioteca-de-cache-nas-apis)
5. [Configuração do Redis por API](#5-configuração-do-redis-por-api)
6. [Implementação nos Controllers e Services](#6-implementação-nos-controllers-e-services)
7. [Estratégias de Invalidação de Cache](#7-estratégias-de-invalidação-de-cache)
8. [Implementação do API Gateway Kong](#8-implementação-do-api-gateway-kong)
9. [Configuração de Rotas e Plugins no Kong](#9-configuração-de-rotas-e-plugins-no-kong)
10. [Health Checks](#10-health-checks)
11. [Passo a Passo de Execução](#11-passo-a-passo-de-execução)
12. [Testes e Validação](#12-testes-e-validação)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Contexto e Escopo

### O que já temos

- A biblioteca **RedisCache.Library** (`FCGLibCache`) publicada no NuGet.org
- Microserviços: **UsersAPI**, **PaymentAPI**, **CatalogAPI**, **NotificationsAPI**
- Documentação da lib: `ESPECIFICACAO_LIB_CACHE.md`, `CRIACAO_E_IMPLEMENTACAO.md`, `PUBLICACAO_E_USO.md`, `UTILIZACAO_NAS_APIS.md`

### O que vamos implementar

- ✅ Instalar e configurar a `FCGLibCache` em cada API
- ✅ Implementar o padrão Cache-Aside nos endpoints de leitura
- ✅ Implementar invalidação de cache nos endpoints de escrita
- ✅ Subir infraestrutura Redis via Docker
- ✅ Configurar o Kong API Gateway como ponto de entrada único
- ✅ Configurar plugins do Kong (rate limiting, CORS, logging)

### Arquitetura Alvo

```
                          ┌──────────────────┐
                          │   Kong Gateway   │
      Clientes ─────────► │   porta: 8000    │
                          └────────┬─────────┘
                                   │
              ┌────────────┬───────┴───────┬────────────┐
              │            │               │            │
        ┌─────▼───┐  ┌─────▼───┐   ┌──────▼──┐  ┌──────▼────────┐
        │ UsersAPI│  │PaymentAPI│   │CatalogAPI│  │NotificationsAPI│
        │  :5001  │  │  :5002   │   │  :5003   │  │    :5004       │
        └────┬────┘  └────┬─────┘   └────┬─────┘  └──────┬────────┘
             │            │              │               │
             └────────────┴──────┬───────┴───────────────┘
                                 │
                          ┌──────▼──────┐
                          │    Redis    │
                          │  porta:6379 │
                          └──────┬──────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │            │
               ┌────▼──┐  ┌────▼──┐   ┌────▼──┐
               │ DB 1  │  │ DB 2  │   │ DB 3  │
               └───────┘  └───────┘   └───────┘
```

### Prefixos de Cache por API

| API              | KeyPrefix        | Porta |
|------------------|------------------|-------|
| UsersAPI         | `users:`         | 5001  |
| PaymentAPI       | `payments:`      | 5002  |
| CatalogAPI       | `catalog:`       | 5003  |
| NotificationsAPI | `notifications:` | 5004  |

---

## 2. Pré-requisitos

### Ferramentas necessárias

| Ferramenta | Versão Mínima | Verificação |
|---|---|---|
| .NET SDK | 6.0+ | `dotnet --version` |
| Docker | 20.10+ | `docker --version` |
| Docker Compose | 2.0+ | `docker compose version` |
| curl | qualquer | `curl --version` |
| jq (opcional) | qualquer | `jq --version` |

### Verificar tudo de uma vez

```bash
echo "=== Verificando pré-requisitos ==="
echo -n ".NET SDK: " && dotnet --version
echo -n "Docker: " && docker --version
echo -n "Docker Compose: " && docker compose version
echo -n "curl: " && curl --version | head -1
echo -n "jq: " && (jq --version 2>/dev/null || echo "não instalado (opcional)")
```

---

## 3. Infraestrutura com Docker Compose

### 3.1. Configuração do Redis

Crie o arquivo de configuração do Redis:

```bash
mkdir -p config/redis
```

```conf
# filepath: config/redis/redis.conf

# ─── REDE ────────────────────────────────────────────────
bind 0.0.0.0
port 6379
protected-mode no

# ─── MEMÓRIA ─────────────────────────────────────────────
# Ajuste conforme o ambiente. 256mb é suficiente para dev/staging.
maxmemory 256mb

# Política de eviction: remove chaves menos usadas recentemente
# quando a memória atinge o limite. Ideal para cache.
maxmemory-policy allkeys-lru

# ─── PERSISTÊNCIA ───────────────────────────────────────
# Salvar snapshot a cada 900s se ao menos 1 chave mudou
save 900 1
save 300 10
save 60 10000

# Append Only File para durabilidade
appendonly yes
appendfsync everysec

# ─── PERFORMANCE ────────────────────────────────────────
tcp-keepalive 300
timeout 0
databases 16

# ─── LOGGING ────────────────────────────────────────────
loglevel notice
logfile ""
```

### 3.2. Docker Compose

```yaml
# filepath: docker-compose.yml
version: '3.8'

services:
  # ═══════════════════════════════════════════════════════
  # REDIS
  # ═══════════════════════════════════════════════════════
  redis:
    image: redis:7-alpine
    container_name: orchestrator-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
      - ./config/redis/redis.conf:/usr/local/etc/redis/redis.conf
    command: redis-server /usr/local/etc/redis/redis.conf
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - orchestrator-net
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'

  # Redis Commander — Interface visual para inspecionar o cache
  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: orchestrator-redis-ui
    environment:
      - REDIS_HOSTS=local:redis:6379
    ports:
      - "8081:8081"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - orchestrator-net

  # ═══════════════════════════════════════════════════════
  # KONG — DATABASE
  # ═══════════════════════════════════════════════════════
  kong-database:
    image: postgres:15-alpine
    container_name: orchestrator-kong-db
    environment:
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong_db_pass
      POSTGRES_DB: kong
    volumes:
      - kong_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kong"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - orchestrator-net

  # ═══════════════════════════════════════════════════════
  # KONG — MIGRATIONS (roda uma vez e sai)
  # ═══════════════════════════════════════════════════════
  kong-migration:
    image: kong:3.6
    container_name: orchestrator-kong-migration
    depends_on:
      kong-database:
        condition: service_healthy
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_db_pass
      KONG_PG_DATABASE: kong
    command: kong migrations bootstrap
    networks:
      - orchestrator-net

  # ═══════════════════════════════════════════════════════
  # KONG — API GATEWAY
  # ═══════════════════════════════════════════════════════
  kong:
    image: kong:3.6
    container_name: orchestrator-kong
    depends_on:
      kong-database:
        condition: service_healthy
      kong-migration:
        condition: service_completed_successfully
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong_db_pass
      KONG_PG_DATABASE: kong
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
      KONG_ADMIN_GUI_URL: http://localhost:8002
      KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl
    ports:
      - "8000:8000"   # Proxy — ponto de entrada das APIs
      - "8443:8443"   # Proxy HTTPS
      - "8001:8001"   # Admin API
      - "8002:8002"   # Kong Manager (GUI)
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
    networks:
      - orchestrator-net
    restart: on-failure

volumes:
  redis_data:
    driver: local
  kong_db_data:
    driver: local

networks:
  orchestrator-net:
    driver: bridge
```

### 3.3. Subir a infraestrutura

```bash
# Subir Redis + Kong
docker compose up -d

# Verificar se tudo está healthy
docker compose ps

# Aguardar todos os serviços ficarem saudáveis
echo "Aguardando Redis..."
until docker exec orchestrator-redis redis-cli ping | grep -q PONG; do sleep 1; done
echo "✅ Redis OK"

echo "Aguardando Kong..."
until curl -s http://localhost:8001/status > /dev/null 2>&1; do sleep 2; done
echo "✅ Kong OK"
```

---

## 4. Instalação da Biblioteca de Cache nas APIs

### 4.1. Instalar o pacote NuGet em cada API

Execute o comando abaixo **dentro da pasta de cada projeto de API**:

```bash
# UsersAPI
cd src/UsersAPI
dotnet add package FCGLibCache
dotnet add package AspNetCore.HealthChecks.Redis

# PaymentAPI
cd ../PaymentAPI
dotnet add package FCGLibCache
dotnet add package AspNetCore.HealthChecks.Redis

# CatalogAPI
cd ../CatalogAPI
dotnet add package FCGLibCache
dotnet add package AspNetCore.HealthChecks.Redis

# NotificationsAPI
cd ../NotificationsAPI
dotnet add package FCGLibCache
dotnet add package AspNetCore.HealthChecks.Redis
```

> **Nota:** Se os projetos estiverem em outra estrutura de pastas, ajuste os caminhos conforme necessário.

### 4.2. Script para instalar em todos de uma vez

```bash
#!/bin/bash
# filepath: scripts/install-cache-packages.sh

APIS=("UsersAPI" "PaymentAPI" "CatalogAPI" "NotificationsAPI")
BASE_PATH="src"

for api in "${APIS[@]}"; do
    echo "📦 Instalando pacotes em $api..."
    cd "$BASE_PATH/$api" 2>/dev/null || { echo "⚠️  Pasta $BASE_PATH/$api não encontrada, pulando..."; continue; }
    dotnet add package FCGLibCache
    dotnet add package AspNetCore.HealthChecks.Redis
    cd - > /dev/null
    echo "✅ $api configurado!"
    echo ""
done

echo "🎉 Instalação concluída em todas as APIs!"
```

```bash
chmod +x scripts/install-cache-packages.sh
./scripts/install-cache-packages.sh
```

---

## 5. Configuração do Redis por API

### 5.1. appsettings.json — Configuração padrão

Adicione a seção `ConnectionStrings` em cada API. O bloco abaixo se aplica a **todas as APIs** — a única diferença é o `KeyPrefix` configurado no `Program.cs`.

```json
// Adicionar ao appsettings.json de CADA API
{
  "ConnectionStrings": {
    "Redis": "localhost:6379"
  }
}
```

#### Para ambiente Docker (appsettings.Docker.json ou variável de ambiente)

```json
{
  "ConnectionStrings": {
    "Redis": "redis:6379"
  }
}
```

### 5.2. appsettings.Development.json — Configuração de desenvolvimento

```json
{
  "ConnectionStrings": {
    "Redis": "localhost:6379"
  },
  "Logging": {
    "LogLevel": {
      "RedisCache.Library": "Debug"
    }
  }
}
```

### 5.3. Program.cs — Registro do serviço de cache

#### UsersAPI

```csharp
// filepath: src/UsersAPI/Program.cs
using RedisCache.Library.Extensions;

var builder = WebApplication.CreateBuilder(args);

// ─── Serviços existentes ────────────────────────────────
// ...existing code...

// ─── Cache Redis ────────────────────────────────────────
builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("Redis")!;
    options.KeyPrefix = "users:";
    options.DefaultExpirationInMinutes = 30;
    options.Enabled = true;
});

// ─── Health Checks ──────────────────────────────────────
builder.Services.AddHealthChecks()
    .AddRedis(
        builder.Configuration.GetConnectionString("Redis")!,
        name: "redis",
        tags: new[] { "cache", "infrastructure" });

// ...existing code...

var app = builder.Build();

// ─── Health Check endpoint ──────────────────────────────
app.MapHealthChecks("/health");

// ...existing code...

app.Run();
```

#### PaymentAPI

```csharp
// filepath: src/PaymentAPI/Program.cs
using RedisCache.Library.Extensions;

var builder = WebApplication.CreateBuilder(args);

// ...existing code...

builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("Redis")!;
    options.KeyPrefix = "payments:";
    options.DefaultExpirationInMinutes = 15; // Pagamentos: TTL menor por segurança
    options.Enabled = true;
});

builder.Services.AddHealthChecks()
    .AddRedis(
        builder.Configuration.GetConnectionString("Redis")!,
        name: "redis",
        tags: new[] { "cache", "infrastructure" });

// ...existing code...

var app = builder.Build();
app.MapHealthChecks("/health");

// ...existing code...

app.Run();
```

#### CatalogAPI

```csharp
// filepath: src/CatalogAPI/Program.cs
using RedisCache.Library.Extensions;

var builder = WebApplication.CreateBuilder(args);

// ...existing code...

builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("Redis")!;
    options.KeyPrefix = "catalog:";
    options.DefaultExpirationInMinutes = 60; // Catálogo muda pouco — TTL maior
    options.Enabled = true;
});

builder.Services.AddHealthChecks()
    .AddRedis(
        builder.Configuration.GetConnectionString("Redis")!,
        name: "redis",
        tags: new[] { "cache", "infrastructure" });

// ...existing code...

var app = builder.Build();
app.MapHealthChecks("/health");

// ...existing code...

app.Run();
```

#### NotificationsAPI

```csharp
// filepath: src/NotificationsAPI/Program.cs
using RedisCache.Library.Extensions;

var builder = WebApplication.CreateBuilder(args);

// ...existing code...

builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("Redis")!;
    options.KeyPrefix = "notifications:";
    options.DefaultExpirationInMinutes = 10; // Notificações: dados mais voláteis
    options.Enabled = true;
});

builder.Services.AddHealthChecks()
    .AddRedis(
        builder.Configuration.GetConnectionString("Redis")!,
        name: "redis",
        tags: new[] { "cache", "infrastructure" });

// ...existing code...

var app = builder.Build();
app.MapHealthChecks("/health");

// ...existing code...

app.Run();
```

### 5.4. Resumo de TTLs por API

| API              | KeyPrefix        | TTL Padrão | Justificativa |
|------------------|------------------|------------|---------------|
| UsersAPI         | `users:`         | 30 min     | Dados de perfil mudam moderadamente |
| PaymentAPI       | `payments:`      | 15 min     | Dados financeiros — consistência é prioridade |
| CatalogAPI       | `catalog:`       | 60 min     | Produtos/categorias mudam pouco |
| NotificationsAPI | `notifications:` | 10 min     | Dados voláteis, preferências podem mudar |

---

## 6. Implementação nos Controllers e Services

### 6.1. Padrão geral de implementação

Para **cada endpoint de leitura** (GET), use o padrão `GetOrSetAsync`:

```
1. Receber request
2. Montar cache key: "{entidade}:{id}"
3. Chamar _cacheService.GetOrSetAsync(key, factory, ttl)
4. Retornar resultado
```

Para **cada endpoint de escrita** (POST, PUT, DELETE), invalide o cache:

```
1. Receber request
2. Executar operação no banco
3. Invalidar cache(s) relacionado(s)
4. Retornar resultado
```

### 6.2. UsersAPI — UsersController

```csharp
// filepath: src/UsersAPI/Controllers/UsersController.cs
using Microsoft.AspNetCore.Mvc;
using RedisCache.Library.Interfaces;

namespace UsersAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly ICacheService _cache;
    private readonly IUserRepository _repository;
    private readonly ILogger<UsersController> _logger;

    public UsersController(
        ICacheService cache,
        IUserRepository repository,
        ILogger<UsersController> logger)
    {
        _cache = cache;
        _repository = repository;
        _logger = logger;
    }

    // ─── GET /api/users/{id} ────────────────────────────
    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(int id)
    {
        var user = await _cache.GetOrSetAsync(
            key: $"user:{id}",
            factory: () => _repository.GetByIdAsync(id),
            expiration: TimeSpan.FromMinutes(15));

        return user is not null ? Ok(user) : NotFound();
    }

    // ─── GET /api/users ─────────────────────────────────
    [HttpGet]
    public async Task<IActionResult> GetAll(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20)
    {
        var cacheKey = $"user:list:p{page}:s{pageSize}";

        var users = await _cache.GetOrSetAsync(
            key: cacheKey,
            factory: () => _repository.GetPagedAsync(page, pageSize),
            expiration: TimeSpan.FromMinutes(5)); // Listas expiram mais rápido

        return Ok(users);
    }

    // ─── GET /api/users/{id}/profile ────────────────────
    [HttpGet("{id}/profile")]
    public async Task<IActionResult> GetProfile(int id)
    {
        var profile = await _cache.GetOrSetAsync(
            key: $"user:{id}:profile",
            factory: () => _repository.GetProfileAsync(id),
            expiration: TimeSpan.FromMinutes(30));

        return profile is not null ? Ok(profile) : NotFound();
    }

    // ─── POST /api/users ────────────────────────────────
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateUserRequest request)
    {
        var user = await _repository.CreateAsync(request);

        // Invalidar listas — novo usuário altera paginação
        await _cache.RemoveByPrefixAsync("user:list:");

        return CreatedAtAction(nameof(GetById), new { id = user.Id }, user);
    }

    // ─── PUT /api/users/{id} ────────────────────────────
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(int id, [FromBody] UpdateUserRequest request)
    {
        await _repository.UpdateAsync(id, request);

        // Invalidar: cache do item + profile + listas
        await _cache.RemoveAsync($"user:{id}");
        await _cache.RemoveAsync($"user:{id}:profile");
        await _cache.RemoveByPrefixAsync("user:list:");

        _logger.LogInformation("Cache invalidado para user:{Id} após atualização", id);

        return NoContent();
    }

    // ─── DELETE /api/users/{id} ─────────────────────────
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _repository.DeleteAsync(id);

        // Invalidar tudo relacionado ao usuário
        await _cache.RemoveAsync($"user:{id}");
        await _cache.RemoveAsync($"user:{id}:profile");
        await _cache.RemoveByPrefixAsync("user:list:");

        _logger.LogInformation("Cache invalidado para user:{Id} após exclusão", id);

        return NoContent();
    }
}
```

### 6.3. PaymentAPI — PaymentsController

```csharp
// filepath: src/PaymentAPI/Controllers/PaymentsController.cs
using Microsoft.AspNetCore.Mvc;
using RedisCache.Library.Interfaces;

namespace PaymentAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PaymentsController : ControllerBase
{
    private readonly ICacheService _cache;
    private readonly IPaymentRepository _repository;
    private readonly ILogger<PaymentsController> _logger;

    public PaymentsController(
        ICacheService cache,
        IPaymentRepository repository,
        ILogger<PaymentsController> logger)
    {
        _cache = cache;
        _repository = repository;
        _logger = logger;
    }

    // ─── GET /api/payments/{id} ─────────────────────────
    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var payment = await _cache.GetOrSetAsync(
            key: $"payment:{id}",
            factory: () => _repository.GetByIdAsync(id),
            expiration: TimeSpan.FromMinutes(10));

        return payment is not null ? Ok(payment) : NotFound();
    }

    // ─── GET /api/payments/user/{userId} ────────────────
    [HttpGet("user/{userId}")]
    public async Task<IActionResult> GetByUserId(int userId)
    {
        var payments = await _cache.GetOrSetAsync(
            key: $"payment:user:{userId}",
            factory: () => _repository.GetByUserIdAsync(userId),
            expiration: TimeSpan.FromMinutes(5));

        return Ok(payments);
    }

    // ─── POST /api/payments ─────────────────────────────
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreatePaymentRequest request)
    {
        var payment = await _repository.CreateAsync(request);

        // Invalidar lista de pagamentos do usuário
        await _cache.RemoveAsync($"payment:user:{request.UserId}");
        await _cache.RemoveByPrefixAsync("payment:list:");

        return CreatedAtAction(nameof(GetById), new { id = payment.Id }, payment);
    }

    // ─── PUT /api/payments/{id}/status ──────────────────
    [HttpPut("{id}/status")]
    public async Task<IActionResult> UpdateStatus(Guid id, [FromBody] UpdatePaymentStatusRequest request)
    {
        var payment = await _repository.GetByIdAsync(id);
        if (payment is null) return NotFound();

        await _repository.UpdateStatusAsync(id, request.Status);

        // Invalidar cache do pagamento e da lista do usuário
        await _cache.RemoveAsync($"payment:{id}");
        await _cache.RemoveAsync($"payment:user:{payment.UserId}");

        _logger.LogInformation(
            "Cache invalidado para payment:{Id} — status: {Status}",
            id, request.Status);

        return NoContent();
    }
}
```

### 6.4. CatalogAPI — ProductsController

```csharp
// filepath: src/CatalogAPI/Controllers/ProductsController.cs
using Microsoft.AspNetCore.Mvc;
using RedisCache.Library.Interfaces;

namespace CatalogAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    private readonly ICacheService _cache;
    private readonly IProductRepository _repository;
    private readonly ILogger<ProductsController> _logger;

    public ProductsController(
        ICacheService cache,
        IProductRepository repository,
        ILogger<ProductsController> logger)
    {
        _cache = cache;
        _repository = repository;
        _logger = logger;
    }

    // ─── GET /api/products/{id} ─────────────────────────
    [HttpGet("{id}")]
    public async Task<IActionResult> GetById(Guid id)
    {
        var product = await _cache.GetOrSetAsync(
            key: $"product:{id}",
            factory: () => _repository.GetByIdAsync(id),
            expiration: TimeSpan.FromMinutes(60)); // Produtos mudam pouco

        return product is not null ? Ok(product) : NotFound();
    }

    // ─── GET /api/products ──────────────────────────────
    [HttpGet]
    public async Task<IActionResult> GetAll(
        [FromQuery] int page = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? category = null)
    {
        var cacheKey = category is not null
            ? $"product:list:cat:{category}:p{page}:s{pageSize}"
            : $"product:list:p{page}:s{pageSize}";

        var products = await _cache.GetOrSetAsync(
            key: cacheKey,
            factory: () => _repository.GetPagedAsync(page, pageSize, category),
            expiration: TimeSpan.FromMinutes(10));

        return Ok(products);
    }

    // ─── GET /api/products/categories ───────────────────
    [HttpGet("categories")]
    public async Task<IActionResult> GetCategories()
    {
        var categories = await _cache.GetOrSetAsync(
            key: "product:categories",
            factory: () => _repository.GetCategoriesAsync(),
            expiration: TimeSpan.FromHours(2)); // Categorias quase nunca mudam

        return Ok(categories);
    }

    // ─── GET /api/products/search?q=termo ───────────────
    [HttpGet("search")]
    public async Task<IActionResult> Search([FromQuery] string q)
    {
        // Para buscas, usar TTL curto — resultados podem variar muito
        var cacheKey = $"product:search:{q.ToLowerInvariant().Trim()}";

        var results = await _cache.GetOrSetAsync(
            key: cacheKey,
            factory: () => _repository.SearchAsync(q),
            expiration: TimeSpan.FromMinutes(2));

        return Ok(results);
    }

    // ─── POST /api/products ─────────────────────────────
    [HttpPost]
    public async Task<IActionResult> Create([FromBody] CreateProductRequest request)
    {
        var product = await _repository.CreateAsync(request);

        // Invalidar listas e categorias
        await _cache.RemoveByPrefixAsync("product:list:");
        await _cache.RemoveByPrefixAsync("product:search:");
        await _cache.RemoveAsync("product:categories");

        return CreatedAtAction(nameof(GetById), new { id = product.Id }, product);
    }

    // ─── PUT /api/products/{id} ─────────────────────────
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(Guid id, [FromBody] UpdateProductRequest request)
    {
        await _repository.UpdateAsync(id, request);

        // Invalidar cache do produto + todas as listas e buscas
        await _cache.RemoveAsync($"product:{id}");
        await _cache.RemoveByPrefixAsync("product:list:");
        await _cache.RemoveByPrefixAsync("product:search:");

        // Se a categoria mudou, invalidar também
        if (request.Category is not null)
        {
            await _cache.RemoveAsync("product:categories");
        }

        _logger.LogInformation("Cache invalidado para product:{Id}", id);

        return NoContent();
    }

    // ─── DELETE /api/products/{id} ──────────────────────
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(Guid id)
    {
        await _repository.DeleteAsync(id);

        await _cache.RemoveAsync($"product:{id}");
        await _cache.RemoveByPrefixAsync("product:list:");
        await _cache.RemoveByPrefixAsync("product:search:");
        await _cache.RemoveAsync("product:categories");

        return NoContent();
    }
}
```

### 6.5. NotificationsAPI — NotificationsController

```csharp
// filepath: src/NotificationsAPI/Controllers/NotificationsController.cs
using Microsoft.AspNetCore.Mvc;
using RedisCache.Library.Interfaces;

namespace NotificationsAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public class NotificationsController : ControllerBase
{
    private readonly ICacheService _cache;
    private readonly INotificationRepository _repository;
    private readonly ILogger<NotificationsController> _logger;

    public NotificationsController(
        ICacheService cache,
        INotificationRepository repository,
        ILogger<NotificationsController> logger)
    {
        _cache = cache;
        _repository = repository;
        _logger = logger;
    }

    // ─── GET /api/notifications/user/{userId} ───────────
    [HttpGet("user/{userId}")]
    public async Task<IActionResult> GetByUserId(int userId, [FromQuery] bool unreadOnly = false)
    {
        var cacheKey = unreadOnly
            ? $"notification:user:{userId}:unread"
            : $"notification:user:{userId}:all";

        var notifications = await _cache.GetOrSetAsync(
            key: cacheKey,
            factory: () => _repository.GetByUserIdAsync(userId, unreadOnly),
            expiration: TimeSpan.FromMinutes(5));

        return Ok(notifications);
    }

    // ─── GET /api/notifications/preferences/{userId} ───
    [HttpGet("preferences/{userId}")]
    public async Task<IActionResult> GetPreferences(int userId)
    {
        var prefs = await _cache.GetOrSetAsync(
            key: $"notification:prefs:{userId}",
            factory: () => _repository.GetPreferencesAsync(userId),
            expiration: TimeSpan.FromMinutes(30));

        return prefs is not null ? Ok(prefs) : NotFound();
    }

    // ─── POST /api/notifications ────────────────────────
    [HttpPost]
    public async Task<IActionResult> Send([FromBody] SendNotificationRequest request)
    {
        var notification = await _repository.CreateAsync(request);

        // Invalidar cache de notificações do usuário
        await _cache.RemoveAsync($"notification:user:{request.UserId}:all");
        await _cache.RemoveAsync($"notification:user:{request.UserId}:unread");

        return CreatedAtAction(
            nameof(GetByUserId),
            new { userId = request.UserId },
            notification);
    }

    // ─── PUT /api/notifications/{id}/read ───────────────
    [HttpPut("{id}/read")]
    public async Task<IActionResult> MarkAsRead(Guid id)
    {
        var notification = await _repository.GetByIdAsync(id);
        if (notification is null) return NotFound();

        await _repository.MarkAsReadAsync(id);

        // Invalidar cache de notificações não lidas do usuário
        await _cache.RemoveAsync($"notification:user:{notification.UserId}:all");
        await _cache.RemoveAsync($"notification:user:{notification.UserId}:unread");

        return NoContent();
    }

    // ─── PUT /api/notifications/preferences/{userId} ───
    [HttpPut("preferences/{userId}")]
    public async Task<IActionResult> UpdatePreferences(
        int userId,
        [FromBody] UpdatePreferencesRequest request)
    {
        await _repository.UpdatePreferencesAsync(userId, request);
        await _cache.RemoveAsync($"notification:prefs:{userId}");

        return NoContent();
    }
}
```

### 6.6. Uso em camada de Services (alternativa aos Controllers)

Se você utiliza uma camada de Services separada (recomendado para lógica de negócio complexa), injete o `ICacheService` no Service em vez do Controller:

```csharp
// filepath: src/CatalogAPI/Services/ProductService.cs
using RedisCache.Library.Interfaces;

namespace CatalogAPI.Services;

public class ProductService : IProductService
{
    private readonly ICacheService _cache;
    private readonly IProductRepository _repository;
    private readonly ILogger<ProductService> _logger;

    public ProductService(
        ICacheService cache,
        IProductRepository repository,
        ILogger<ProductService> logger)
    {
        _cache = cache;
        _repository = repository;
        _logger = logger;
    }

    public async Task<ProductDto?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        return await _cache.GetOrSetAsync(
            key: $"product:{id}",
            factory: async () =>
            {
                var entity = await _repository.GetByIdAsync(id);
                return entity is null ? default! : MapToDto(entity);
            },
            expiration: TimeSpan.FromMinutes(60));
    }

    public async Task<ProductDto> CreateAsync(CreateProductRequest request, CancellationToken ct = default)
    {
        var entity = await _repository.CreateAsync(request);
        var dto = MapToDto(entity);

        // Cache o item recém-criado (write-through)
        await _cache.SetAsync($"product:{entity.Id}", dto, TimeSpan.FromMinutes(60));

        // Invalidar listas
        await _cache.RemoveByPrefixAsync("product:list:");
        await _cache.RemoveByPrefixAsync("product:search:");

        return dto;
    }

    private static ProductDto MapToDto(Product entity) =>
        new(entity.Id, entity.Name, entity.Price, entity.Category, entity.CreatedAt);
}
```

---

## 7. Estratégias de Invalidação de Cache

### 7.1. Mapa de Invalidação por Operação

#### UsersAPI

| Operação | Chaves invalidadas |
|---|---|
| `POST /api/users` | `user:list:*` |
| `PUT /api/users/{id}` | `user:{id}`, `user:{id}:profile`, `user:list:*` |
| `DELETE /api/users/{id}` | `user:{id}`, `user:{id}:profile`, `user:list:*` |

#### PaymentAPI

| Operação | Chaves invalidadas |
|---|---|
| `POST /api/payments` | `payment:user:{userId}`, `payment:list:*` |
| `PUT /api/payments/{id}/status` | `payment:{id}`, `payment:user:{userId}` |

#### CatalogAPI

| Operação | Chaves invalidadas |
|---|---|
| `POST /api/products` | `product:list:*`, `product:search:*`, `product:categories` |
| `PUT /api/products/{id}` | `product:{id}`, `product:list:*`, `product:search:*`, `product:categories` (se mudou categoria) |
| `DELETE /api/products/{id}` | `product:{id}`, `product:list:*`, `product:search:*`, `product:categories` |

#### NotificationsAPI

| Operação | Chaves invalidadas |
|---|---|
| `POST /api/notifications` | `notification:user:{userId}:all`, `notification:user:{userId}:unread` |
| `PUT /api/notifications/{id}/read` | `notification:user:{userId}:all`, `notification:user:{userId}:unread` |
| `PUT /api/notifications/preferences/{userId}` | `notification:prefs:{userId}` |

### 7.2. Regras de Ouro para Invalidação

```
1. SEMPRE invalide o cache do item individual após escrita
2. SEMPRE invalide caches de lista após criar/deletar itens
3. NUNCA confie apenas no TTL para dados que mudaram — invalide ativamente
4. Use RemoveByPrefixAsync para invalidar grupos de chaves relacionadas
5. Em caso de dúvida, invalide mais do que menos — cache miss é melhor que dado stale
```

### 7.3. Diagrama de Fluxo: Leitura com Cache

```
                    Request GET /api/products/123
                              │
                              ▼
                    ┌──────────────────┐
                    │ _cache.GetOrSet  │
                    │   Async(key,     │
                    │   factory, ttl)  │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │  Existe no Redis? │
                    └────┬────────┬────┘
                         │        │
                       SIM       NÃO
                         │        │
                    ┌────▼──┐  ┌──▼─────────────┐
                    │Return │  │ Executa factory │
                    │cached │  │ (query no DB)   │
                    │ value │  └──────┬──────────┘
                    └───────┘         │
                                ┌─────▼─────────┐
                                │ Armazena no   │
                                │ Redis com TTL │
                                └─────┬─────────┘
                                      │
                                ┌─────▼─────────┐
                                │ Return value  │
                                └───────────────┘
```

### 7.4. Diagrama de Fluxo: Escrita com Invalidação

```
                    Request PUT /api/products/123
                              │
                              ▼
                    ┌──────────────────┐
                    │ _repository      │
                    │  .UpdateAsync()  │
                    └────────┬─────────┘
                             │
                    ┌────────▼──────────┐
                    │ DB atualizado     │
                    │ com sucesso?      │
                    └────┬─────────┬────┘
                         │         │
                       SIM        NÃO
                         │         │
              ┌──────────▼──┐   ┌──▼──────┐
              │ Invalidar:  │   │ Return  │
              │ • product:  │   │ Error   │
              │   {id}      │   └─────────┘
              │ • product:  │
              │   list:*    │
              │ • product:  │
              │   search:*  │
              └──────┬──────┘
                     │
              ┌──────▼──────┐
              │ Return 204  │
              │ NoContent   │
              └─────────────┘
```

---

## 8. Implementação do API Gateway Kong

### 8.1. Script de Configuração

Crie o diretório e o script:

```bash
mkdir -p scripts/kong
```

```bash
#!/bin/bash
# filepath: scripts/kong/setup-kong.sh

KONG_ADMIN="http://localhost:8001"

echo "════════════════════════════════════════════════"
echo "  🦍 Configurando Kong API Gateway"
echo "════════════════════════════════════════════════"
echo ""

# ── Aguardar Kong ────────────────────────────────────────
echo "⏳ Aguardando Kong ficar disponível..."
until curl -s "$KONG_ADMIN/status" > /dev/null 2>&1; do
    printf '.'
    sleep 2
done
echo ""
echo "✅ Kong está pronto!"
echo ""

# ═════════════════════════════════════════════════════════
# SERVIÇOS
# ═════════════════════════════════════════════════════════

echo "📦 Registrando serviços..."

# UsersAPI
curl -s -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "users-service",
    "url": "http://host.docker.internal:5001",
    "connect_timeout": 10000,
    "read_timeout": 30000,
    "write_timeout": 30000,
    "retries": 3
  }' | jq -r '.name // .message' 2>/dev/null || true

# PaymentAPI
curl -s -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "payment-service",
    "url": "http://host.docker.internal:5002",
    "connect_timeout": 10000,
    "read_timeout": 30000,
    "write_timeout": 30000,
    "retries": 3
  }' | jq -r '.name // .message' 2>/dev/null || true

# CatalogAPI
curl -s -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "catalog-service",
    "url": "http://host.docker.internal:5003",
    "connect_timeout": 10000,
    "read_timeout": 30000,
    "write_timeout": 30000,
    "retries": 3
  }' | jq -r '.name // .message' 2>/dev/null || true

# NotificationsAPI
curl -s -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "notification-service",
    "url": "http://host.docker.internal:5004",
    "connect_timeout": 10000,
    "read_timeout": 30000,
    "write_timeout": 30000,
    "retries": 3
  }' | jq -r '.name // .message' 2>/dev/null || true

echo "✅ Serviços registrados!"
echo ""

# ═════════════════════════════════════════════════════════
# ROTAS
# ═════════════════════════════════════════════════════════

echo "🛤️  Registrando rotas..."

# UsersAPI — /api/users/**
curl -s -X POST "$KONG_ADMIN/services/users-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "users-route",
    "paths": ["/api/users"],
    "strip_path": false,
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"]
  }' | jq -r '.name // .message' 2>/dev/null || true

# PaymentAPI — /api/payments/**
curl -s -X POST "$KONG_ADMIN/services/payment-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "payments-route",
    "paths": ["/api/payments"],
    "strip_path": false,
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"]
  }' | jq -r '.name // .message' 2>/dev/null || true

# CatalogAPI — /api/products/**
curl -s -X POST "$KONG_ADMIN/services/catalog-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "products-route",
    "paths": ["/api/products"],
    "strip_path": false,
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"]
  }' | jq -r '.name // .message' 2>/dev/null || true

# NotificationsAPI — /api/notifications/**
curl -s -X POST "$KONG_ADMIN/services/notification-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "notifications-route",
    "paths": ["/api/notifications"],
    "strip_path": false,
    "methods": ["GET", "POST", "PUT", "DELETE"]
  }' | jq -r '.name // .message' 2>/dev/null || true

echo "✅ Rotas registradas!"
echo ""

# ═════════════════════════════════════════════════════════
# PLUGINS GLOBAIS
# ═════════════════════════════════════════════════════════

echo "🔌 Configurando plugins globais..."

# 1. Rate Limiting (usando Redis para estado compartilhado)
curl -s -X POST "$KONG_ADMIN/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting",
    "config": {
      "minute": 100,
      "hour": 5000,
      "policy": "redis",
      "redis_host": "orchestrator-redis",
      "redis_port": 6379,
      "redis_database": 1,
      "fault_tolerant": true,
      "hide_client_headers": false
    }
  }' | jq -r '.name // .message' 2>/dev/null || true
echo "   ✓ Rate Limiting (100/min, 5000/h)"

# 2. CORS
curl -s -X POST "$KONG_ADMIN/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cors",
    "config": {
      "origins": ["*"],
      "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
      "headers": ["Authorization", "Content-Type", "Accept", "X-Request-ID"],
      "exposed_headers": ["X-RateLimit-Limit-Minute", "X-RateLimit-Remaining-Minute"],
      "credentials": false,
      "max_age": 3600
    }
  }' | jq -r '.name // .message' 2>/dev/null || true
echo "   ✓ CORS"

# 3. Correlation ID (rastreamento de requests)
curl -s -X POST "$KONG_ADMIN/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "correlation-id",
    "config": {
      "header_name": "X-Request-ID",
      "generator": "uuid#counter",
      "echo_downstream": true
    }
  }' | jq -r '.name // .message' 2>/dev/null || true
echo "   ✓ Correlation ID"

# 4. Response Transformer (headers de segurança)
curl -s -X POST "$KONG_ADMIN/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "response-transformer",
    "config": {
      "add": {
        "headers": [
          "X-Content-Type-Options:nosniff",
          "X-Frame-Options:DENY",
          "X-XSS-Protection:1; mode=block",
          "X-Gateway:Kong"
        ]
      },
      "remove": {
        "headers": ["Server"]
      }
    }
  }' | jq -r '.name // .message' 2>/dev/null || true
echo "   ✓ Response Transformer (security headers)"

echo ""
echo "✅ Plugins globais configurados!"
echo ""

# ═════════════════════════════════════════════════════════
# PLUGINS POR SERVIÇO
# ═════════════════════════════════════════════════════════

echo "🔌 Configurando rate limiting por serviço..."

# PaymentAPI — rate limiting mais restritivo
curl -s -X POST "$KONG_ADMIN/services/payment-service/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting",
    "config": {
      "minute": 50,
      "hour": 2000,
      "policy": "redis",
      "redis_host": "orchestrator-redis",
      "redis_port": 6379,
      "redis_database": 1,
      "fault_tolerant": true
    }
  }' | jq -r '.name // .message' 2>/dev/null || true
echo "   ✓ PaymentAPI: 50/min, 2000/h"

# NotificationsAPI — rate limiting mais restritivo
curl -s -X POST "$KONG_ADMIN/services/notification-service/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting",
    "config": {
      "minute": 30,
      "hour": 1000,
      "policy": "redis",
      "redis_host": "orchestrator-redis",
      "redis_port": 6379,
      "redis_database": 1,
      "fault_tolerant": true
    }
  }' | jq -r '.name // .message' 2>/dev/null || true
echo "   ✓ NotificationsAPI: 30/min, 1000/h"

echo ""
echo "✅ Rate limiting por serviço configurado!"
echo ""

# ═════════════════════════════════════════════════════════
# VERIFICAÇÃO
# ═════════════════════════════════════════════════════════

echo "🏥 Verificação final..."
echo ""

echo "╔══════════════════════════════════════════════╗"
echo "║  SERVIÇOS REGISTRADOS                        ║"
echo "╚══════════════════════════════════════════════╝"
curl -s "$KONG_ADMIN/services" | jq -r '.data[] | "  • \(.name) → \(.host):\(.port)"' 2>/dev/null || true
echo ""

echo "╔══════════════════════════════════════════════╗"
echo "║  ROTAS REGISTRADAS                           ║"
echo "╚══════════════════════════════════════════════╝"
curl -s "$KONG_ADMIN/routes" | jq -r '.data[] | "  • \(.name) → \(.paths | join(", "))"' 2>/dev/null || true
echo ""

echo "╔══════════════════════════════════════════════╗"
echo "║  PLUGINS ATIVOS                              ║"
echo "╚══════════════════════════════════════════════╝"
curl -s "$KONG_ADMIN/plugins" | jq -r '.data[] | "  • \(.name) [\(if .service then .service.id[:8] else "global" end)]"' 2>/dev/null || true
echo ""

echo "════════════════════════════════════════════════"
echo "  ✅ Kong configurado com sucesso!"
echo "════════════════════════════════════════════════"
echo ""
echo "  📡 Proxy (ponto de entrada): http://localhost:8000"
echo "  🔧 Admin API: