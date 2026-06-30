# Implementação de Cache com Redis e API Gateway com Kong

## Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Implementação do Redis Cache](#2-implementação-do-redis-cache)
3. [Implementação do API Gateway Kong](#3-implementação-do-api-gateway-kong)
4. [Integração entre Redis, Kong e Microserviços](#4-integração-entre-redis-kong-e-microserviços)
5. [Estratégias de Cache](#5-estratégias-de-cache)
6. [Monitoramento e Observabilidade](#6-monitoramento-e-observabilidade)
7. [Troubleshooting](#7-troubleshooting)

---

## 1. Visão Geral da Arquitetura

### Arquitetura Atual (Sem Cache e Sem Gateway)

```
Cliente → Microserviço A → Banco de Dados A
Cliente → Microserviço B → Banco de Dados B
Cliente → Microserviço C → Banco de Dados C
```

### Arquitetura Proposta (Com Redis Cache e Kong API Gateway)

```
                          ┌──────────────┐
                          │   Kong API   │
      Cliente ──────────► │   Gateway    │
                          │  (porta 8000)│
                          └──────┬───────┘
                                 │
                    ┌────────────┼────────────┐
                    │            │             │
              ┌─────▼──┐  ┌─────▼──┐   ┌─────▼──┐
              │ Serviço │  │ Serviço │   │ Serviço │
              │    A    │  │    B    │   │    C    │
              └────┬────┘  └────┬────┘   └────┬────┘
                   │            │              │
              ┌────▼────────────▼──────────────▼────┐
              │          Redis Cache Cluster          │
              │           (porta 6379)                │
              └────┬────────────┬──────────────┬────┘
                   │            │              │
              ┌────▼────┐ ┌────▼────┐   ┌────▼────┐
              │  DB A   │ │  DB B   │   │  DB C   │
              └─────────┘ └─────────┘   └─────────┘
```

### Benefícios Esperados

| Métrica | Sem Cache/Gateway | Com Cache + Kong |
|---|---|---|
| Latência média | 100-500ms | 5-50ms (cache hit) |
| Carga no DB | 100% das requests | ~20-30% das requests |
| Rate limiting | Manual por serviço | Centralizado no Kong |
| Autenticação | Duplicada por serviço | Centralizada no Kong |
| Observabilidade | Fragmentada | Centralizada |

---

## 2. Implementação do Redis Cache

### 2.1. Infraestrutura Redis com Docker Compose

Crie ou atualize o arquivo `docker-compose.yml` na raiz do projeto:

```yaml
# docker-compose.yml
version: '3.8'

services:
  # ─── Redis Cache ───────────────────────────────────────
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
      - orchestrator-network
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'

  # ─── Redis Commander (UI para debug) ──────────────────
  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: orchestrator-redis-commander
    environment:
      - REDIS_HOSTS=local:redis:6379
    ports:
      - "8081:8081"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - orchestrator-network

volumes:
  redis_data:
    driver: local

networks:
  orchestrator-network:
    driver: bridge
```

### 2.2. Configuração do Redis

Crie o arquivo de configuração do Redis:

```conf
# config/redis/redis.conf

# ─── REDE ────────────────────────────────────────────────
bind 0.0.0.0
port 6379
protected-mode yes
requirepass your_redis_password_here

# ─── MEMÓRIA ────────────────────────────────────────────
maxmemory 256mb
maxmemory-policy allkeys-lru

# ─── PERSISTÊNCIA ───────────────────────────────────────
save 900 1
save 300 10
save 60 10000
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

### 2.3. Camada de Cache na Aplicação (.NET)

#### 2.3.1. Instalar pacotes NuGet necessários

```bash
# Na raiz de cada microserviço
dotnet add package Microsoft.Extensions.Caching.StackExchangeRedis
dotnet add package StackExchange.Redis
dotnet add package Newtonsoft.Json
```

#### 2.3.2. Configuração no `appsettings.json`

```json
{
  "Redis": {
    "ConnectionString": "localhost:6379,password=your_redis_password_here,abortConnect=false,connectTimeout=5000,syncTimeout=5000",
    "InstanceName": "Orchestrator:",
    "DefaultExpirationMinutes": 30,
    "SlidingExpirationMinutes": 10
  }
}
```

#### 2.3.3. Modelo de Configuração

```csharp
// src/Shared/Configuration/RedisCacheSettings.cs
namespace Orchestrator.Shared.Configuration;

public class RedisCacheSettings
{
    public const string SectionName = "Redis";
    
    public string ConnectionString { get; set; } = string.Empty;
    public string InstanceName { get; set; } = "Orchestrator:";
    public int DefaultExpirationMinutes { get; set; } = 30;
    public int SlidingExpirationMinutes { get; set; } = 10;
}
```

#### 2.3.4. Interface do Serviço de Cache

```csharp
// src/Shared/Interfaces/ICacheService.cs
namespace Orchestrator.Shared.Interfaces;

public interface ICacheService
{
    /// <summary>
    /// Obtém um valor do cache. Retorna default se não encontrado.
    /// </summary>
    Task<T?> GetAsync<T>(string key, CancellationToken cancellationToken = default);

    /// <summary>
    /// Define um valor no cache com expiração configurável.
    /// </summary>
    Task SetAsync<T>(string key, T value, TimeSpan? expiration = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// Remove um valor do cache.
    /// </summary>
    Task RemoveAsync(string key, CancellationToken cancellationToken = default);

    /// <summary>
    /// Remove todas as chaves que correspondem ao padrão.
    /// </summary>
    Task RemoveByPatternAsync(string pattern, CancellationToken cancellationToken = default);

    /// <summary>
    /// Obtém ou cria um valor no cache (Cache-Aside Pattern).
    /// </summary>
    Task<T?> GetOrSetAsync<T>(
        string key,
        Func<Task<T>> factory,
        TimeSpan? expiration = null,
        CancellationToken cancellationToken = default);

    /// <summary>
    /// Verifica se uma chave existe no cache.
    /// </summary>
    Task<bool> ExistsAsync(string key, CancellationToken cancellationToken = default);
}
```

#### 2.3.5. Implementação do Serviço de Cache

```csharp
// src/Shared/Services/RedisCacheService.cs
using System.Text.Json;
using Microsoft.Extensions.Caching.Distributed;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Orchestrator.Shared.Configuration;
using Orchestrator.Shared.Interfaces;
using StackExchange.Redis;

namespace Orchestrator.Shared.Services;

public class RedisCacheService : ICacheService
{
    private readonly IDistributedCache _distributedCache;
    private readonly IConnectionMultiplexer _connectionMultiplexer;
    private readonly RedisCacheSettings _settings;
    private readonly ILogger<RedisCacheService> _logger;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        WriteIndented = false
    };

    public RedisCacheService(
        IDistributedCache distributedCache,
        IConnectionMultiplexer connectionMultiplexer,
        IOptions<RedisCacheSettings> settings,
        ILogger<RedisCacheService> logger)
    {
        _distributedCache = distributedCache;
        _connectionMultiplexer = connectionMultiplexer;
        _settings = settings.Value;
        _logger = logger;
    }

    public async Task<T?> GetAsync<T>(string key, CancellationToken cancellationToken = default)
    {
        try
        {
            var cachedValue = await _distributedCache.GetStringAsync(key, cancellationToken);

            if (string.IsNullOrEmpty(cachedValue))
            {
                _logger.LogDebug("Cache MISS para chave: {Key}", key);
                return default;
            }

            _logger.LogDebug("Cache HIT para chave: {Key}", key);
            return JsonSerializer.Deserialize<T>(cachedValue, JsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao obter valor do cache para chave: {Key}", key);
            return default; // Falha silenciosa - o sistema continua sem cache
        }
    }

    public async Task SetAsync<T>(
        string key, 
        T value, 
        TimeSpan? expiration = null,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var serializedValue = JsonSerializer.Serialize(value, JsonOptions);

            var options = new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = expiration 
                    ?? TimeSpan.FromMinutes(_settings.DefaultExpirationMinutes),
                SlidingExpiration = TimeSpan.FromMinutes(_settings.SlidingExpirationMinutes)
            };

            await _distributedCache.SetStringAsync(key, serializedValue, options, cancellationToken);
            _logger.LogDebug("Cache SET para chave: {Key}, TTL: {Ttl}", key, options.AbsoluteExpirationRelativeToNow);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao definir valor no cache para chave: {Key}", key);
        }
    }

    public async Task RemoveAsync(string key, CancellationToken cancellationToken = default)
    {
        try
        {
            await _distributedCache.RemoveAsync(key, cancellationToken);
            _logger.LogDebug("Cache REMOVE para chave: {Key}", key);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao remover valor do cache para chave: {Key}", key);
        }
    }

    public async Task RemoveByPatternAsync(string pattern, CancellationToken cancellationToken = default)
    {
        try
        {
            var server = _connectionMultiplexer.GetServer(
                _connectionMultiplexer.GetEndPoints().First());
            var db = _connectionMultiplexer.GetDatabase();

            var keys = server.Keys(pattern: $"{_settings.InstanceName}{pattern}*");
            
            foreach (var key in keys)
            {
                await db.KeyDeleteAsync(key);
                _logger.LogDebug("Cache REMOVE BY PATTERN: {Key}", key);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao remover chaves por padrão: {Pattern}", pattern);
        }
    }

    public async Task<T?> GetOrSetAsync<T>(
        string key,
        Func<Task<T>> factory,
        TimeSpan? expiration = null,
        CancellationToken cancellationToken = default)
    {
        // Tenta obter do cache
        var cached = await GetAsync<T>(key, cancellationToken);
        if (cached is not null)
            return cached;

        // Cache miss - busca do data source
        var value = await factory();

        if (value is not null)
        {
            await SetAsync(key, value, expiration, cancellationToken);
        }

        return value;
    }

    public async Task<bool> ExistsAsync(string key, CancellationToken cancellationToken = default)
    {
        try
        {
            var value = await _distributedCache.GetAsync(key, cancellationToken);
            return value is not null;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao verificar existência da chave: {Key}", key);
            return false;
        }
    }
}
```

#### 2.3.6. Helpers para Geração de Cache Keys

```csharp
// src/Shared/Helpers/CacheKeyHelper.cs
namespace Orchestrator.Shared.Helpers;

/// <summary>
/// Helper para gerar chaves de cache padronizadas e consistentes.
/// Formato: {ServiceName}:{Entity}:{Identifier}
/// </summary>
public static class CacheKeyHelper
{
    public static string ForEntity(string serviceName, string entity, string id)
        => $"{serviceName}:{entity}:{id}";

    public static string ForEntityList(string serviceName, string entity, int page = 1, int pageSize = 20)
        => $"{serviceName}:{entity}:list:p{page}:s{pageSize}";

    public static string ForEntityList(string serviceName, string entity, string filter)
        => $"{serviceName}:{entity}:list:{filter}";

    public static string ForQuery(string serviceName, string queryName, params object[] parameters)
    {
        var paramKey = string.Join(":", parameters.Select(p => p?.ToString() ?? "null"));
        return $"{serviceName}:query:{queryName}:{paramKey}";
    }

    public static string PatternForEntity(string serviceName, string entity)
        => $"{serviceName}:{entity}:*";

    public static string PatternForService(string serviceName)
        => $"{serviceName}:*";
}
```

#### 2.3.7. Registro dos Serviços no DI Container

```csharp
// src/Shared/Extensions/CacheServiceExtensions.cs
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Orchestrator.Shared.Configuration;
using Orchestrator.Shared.Interfaces;
using Orchestrator.Shared.Services;
using StackExchange.Redis;

namespace Orchestrator.Shared.Extensions;

public static class CacheServiceExtensions
{
    public static IServiceCollection AddRedisCache(
        this IServiceCollection services,
        IConfiguration configuration)
    {
        // Bind das configurações
        var redisSettings = configuration
            .GetSection(RedisCacheSettings.SectionName)
            .Get<RedisCacheSettings>()!;

        services.Configure<RedisCacheSettings>(
            configuration.GetSection(RedisCacheSettings.SectionName));

        // Registrar ConnectionMultiplexer como Singleton
        services.AddSingleton<IConnectionMultiplexer>(sp =>
        {
            var configOptions = ConfigurationOptions.Parse(redisSettings.ConnectionString);
            configOptions.AbortOnConnectFail = false;
            configOptions.ConnectRetry = 3;
            configOptions.ReconnectRetryPolicy = new ExponentialRetry(5000);
            return ConnectionMultiplexer.Connect(configOptions);
        });

        // Registrar Distributed Cache com Redis
        services.AddStackExchangeRedisCache(options =>
        {
            options.Configuration = redisSettings.ConnectionString;
            options.InstanceName = redisSettings.InstanceName;
        });

        // Registrar o serviço de cache
        services.AddSingleton<ICacheService, RedisCacheService>();

        return services;
    }
}
```

#### 2.3.8. Uso no `Program.cs` de cada Microserviço

```csharp
// Program.cs
using Orchestrator.Shared.Extensions;

var builder = WebApplication.CreateBuilder(args);

// ... outras configurações ...

// Adicionar Redis Cache
builder.Services.AddRedisCache(builder.Configuration);

// ... resto da configuração ...
var app = builder.Build();
```

#### 2.3.9. Exemplo de Uso em um Repository/Service

```csharp
// src/Services/ProductService/Application/Services/ProductAppService.cs
using Orchestrator.Shared.Helpers;
using Orchestrator.Shared.Interfaces;

namespace ProductService.Application.Services;

public class ProductAppService : IProductAppService
{
    private readonly IProductRepository _repository;
    private readonly ICacheService _cacheService;
    private readonly ILogger<ProductAppService> _logger;

    private const string ServiceName = "product-service";
    private const string EntityName = "product";

    public ProductAppService(
        IProductRepository repository,
        ICacheService cacheService,
        ILogger<ProductAppService> logger)
    {
        _repository = repository;
        _cacheService = cacheService;
        _logger = logger;
    }

    public async Task<ProductDto?> GetByIdAsync(Guid id, CancellationToken ct = default)
    {
        var cacheKey = CacheKeyHelper.ForEntity(ServiceName, EntityName, id.ToString());

        // Cache-Aside Pattern
        return await _cacheService.GetOrSetAsync(
            cacheKey,
            async () =>
            {
                var product = await _repository.GetByIdAsync(id, ct);
                return product is null ? default! : MapToDto(product);
            },
            TimeSpan.FromMinutes(15),
            ct);
    }

    public async Task<IEnumerable<ProductDto>> GetAllAsync(
        int page = 1, 
        int pageSize = 20,
        CancellationToken ct = default)
    {
        var cacheKey = CacheKeyHelper.ForEntityList(ServiceName, EntityName, page, pageSize);

        return await _cacheService.GetOrSetAsync(
            cacheKey,
            async () =>
            {
                var products = await _repository.GetPagedAsync(page, pageSize, ct);
                return products.Select(MapToDto);
            },
            TimeSpan.FromMinutes(5),
            ct) ?? Enumerable.Empty<ProductDto>();
    }

    public async Task<ProductDto> CreateAsync(CreateProductCommand command, CancellationToken ct = default)
    {
        var product = new Product(command.Name, command.Price);
        await _repository.AddAsync(product, ct);

        // Invalidar cache de listas quando um novo item é criado
        await _cacheService.RemoveByPatternAsync(
            $"{ServiceName}:{EntityName}:list");

        var dto = MapToDto(product);

        // Cachear o novo item individualmente
        var cacheKey = CacheKeyHelper.ForEntity(ServiceName, EntityName, product.Id.ToString());
        await _cacheService.SetAsync(cacheKey, dto, TimeSpan.FromMinutes(15), ct);

        return dto;
    }

    public async Task UpdateAsync(Guid id, UpdateProductCommand command, CancellationToken ct = default)
    {
        var product = await _repository.GetByIdAsync(id, ct)
            ?? throw new NotFoundException($"Product {id} not found");

        product.Update(command.Name, command.Price);
        await _repository.UpdateAsync(product, ct);

        // Invalidar cache do item específico E das listas
        var cacheKey = CacheKeyHelper.ForEntity(ServiceName, EntityName, id.ToString());
        await _cacheService.RemoveAsync(cacheKey, ct);
        await _cacheService.RemoveByPatternAsync(
            $"{ServiceName}:{EntityName}:list");
    }

    public async Task DeleteAsync(Guid id, CancellationToken ct = default)
    {
        await _repository.DeleteAsync(id, ct);

        // Invalidar todo cache relacionado a esta entidade
        await _cacheService.RemoveByPatternAsync(
            CacheKeyHelper.PatternForEntity(ServiceName, EntityName));
    }

    private static ProductDto MapToDto(Product product) =>
        new(product.Id, product.Name, product.Price, product.CreatedAt);
}
```

#### 2.3.10. Middleware de Cache para Responses HTTP (Opcional)

```csharp
// src/Shared/Middleware/ResponseCacheMiddleware.cs
using System.Text;
using Microsoft.AspNetCore.Http;
using Orchestrator.Shared.Interfaces;

namespace Orchestrator.Shared.Middleware;

public class ResponseCacheMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ICacheService _cacheService;
    private readonly ILogger<ResponseCacheMiddleware> _logger;

    public ResponseCacheMiddleware(
        RequestDelegate next,
        ICacheService cacheService,
        ILogger<ResponseCacheMiddleware> logger)
    {
        _next = next;
        _cacheService = cacheService;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        // Apenas cachear GET requests
        if (context.Request.Method != HttpMethods.Get)
        {
            await _next(context);
            return;
        }

        var cacheKey = $"response:{context.Request.Path}{context.Request.QueryString}";
        var cachedResponse = await _cacheService.GetAsync<CachedResponse>(cacheKey);

        if (cachedResponse is not null)
        {
            context.Response.StatusCode = cachedResponse.StatusCode;
            context.Response.ContentType = cachedResponse.ContentType;
            context.Response.Headers.Append("X-Cache", "HIT");
            await context.Response.WriteAsync(cachedResponse.Body);
            return;
        }

        // Capturar a response
        var originalBodyStream = context.Response.Body;
        using var responseBody = new MemoryStream();
        context.Response.Body = responseBody;

        await _next(context);

        // Só cachear respostas de sucesso
        if (context.Response.StatusCode == 200)
        {
            responseBody.Seek(0, SeekOrigin.Begin);
            var body = await new StreamReader(responseBody).ReadToEndAsync();

            var cached = new CachedResponse
            {
                StatusCode = context.Response.StatusCode,
                ContentType = context.Response.ContentType ?? "application/json",
                Body = body
            };

            await _cacheService.SetAsync(cacheKey, cached, TimeSpan.FromMinutes(5));
            context.Response.Headers.Append("X-Cache", "MISS");

            responseBody.Seek(0, SeekOrigin.Begin);
        }

        await responseBody.CopyToAsync(originalBodyStream);
    }
}

public class CachedResponse
{
    public int StatusCode { get; set; }
    public string ContentType { get; set; } = string.Empty;
    public string Body { get; set; } = string.Empty;
}
```

---

## 3. Implementação do API Gateway Kong

### 3.1. Infraestrutura Kong com Docker Compose

Adicione os serviços do Kong ao `docker-compose.yml`:

```yaml
# docker-compose.yml (adicionar aos serviços existentes)
version: '3.8'

services:
  # ... serviços Redis anteriores ...

  # ─── Kong Database (PostgreSQL) ────────────────────────
  kong-database:
    image: postgres:15-alpine
    container_name: orchestrator-kong-db
    environment:
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong_password
      POSTGRES_DB: kong
    ports:
      - "5433:5432"
    volumes:
      - kong_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kong"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - orchestrator-network

  # ─── Kong Migrations ──────────────────────────────────
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
      KONG_PG_PASSWORD: kong_password
      KONG_PG_DATABASE: kong
    command: kong migrations bootstrap
    networks:
      - orchestrator-network

  # ─── Kong API Gateway ─────────────────────────────────
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
      KONG_PG_PASSWORD: kong_password
      KONG_PG_DATABASE: kong
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
      KONG_ADMIN_GUI_URL: http://localhost:8002
      KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl
    ports:
      - "8000:8000"   # Proxy HTTP
      - "8443:8443"   # Proxy HTTPS
      - "8001:8001"   # Admin API
      - "8002:8002"   # Kong Manager (GUI)
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
    networks:
      - orchestrator-network
    restart: on-failure

  # ─── Konga (Dashboard alternativo - opcional) ──────────
  konga:
    image: pantsel/konga:latest
    container_name: orchestrator-konga
    depends_on:
      kong:
        condition: service_healthy
    environment:
      NODE_ENV: development
      TOKEN_SECRET: your_konga_secret
    ports:
      - "1337:1337"
    networks:
      - orchestrator-network

volumes:
  redis_data:
    driver: local
  kong_db_data:
    driver: local

networks:
  orchestrator-network:
    driver: bridge
```

### 3.2. Script de Inicialização e Configuração do Kong

Crie um script para configurar as rotas e serviços no Kong:

```bash
#!/bin/bash
# scripts/kong/setup-kong.sh

KONG_ADMIN_URL="http://localhost:8001"

echo "================================================"
echo "  Configurando Kong API Gateway"
echo "================================================"

# Aguardar Kong estar pronto
echo "Aguardando Kong ficar disponível..."
until curl -s "$KONG_ADMIN_URL/status" > /dev/null 2>&1; do
    printf '.'
    sleep 2
done
echo ""
echo "✅ Kong está pronto!"

# ─────────────────────────────────────────────────────────
# 1. REGISTRAR SERVIÇOS
# ─────────────────────────────────────────────────────────

echo ""
echo "📦 Registrando serviços..."

# Serviço de Produtos
curl -s -X POST "$KONG_ADMIN_URL/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "product-service",
    "url": "http://product-service:5001",
    "connect_timeout": 60000,
    "read_timeout": 60000,
    "write_timeout": 60000,
    "retries": 3
  }' | jq .

# Serviço de Pedidos
curl -s -X POST "$KONG_ADMIN_URL/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order-service",
    "url": "http://order-service:5002",
    "connect_timeout": 60000,
    "read_timeout": 60000,
    "write_timeout": 60000,
    "retries": 3
  }' | jq .

# Serviço de Usuários
curl -s -X POST "$KONG_ADMIN_URL/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "user-service",
    "url": "http://user-service:5003",
    "connect_timeout": 60000,
    "read_timeout": 60000,
    "write_timeout": 60000,
    "retries": 3
  }' | jq .

# Serviço de Notificações
curl -s -X POST "$KONG_ADMIN_URL/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "notification-service",
    "url": "http://notification-service:5004",
    "connect_timeout": 60000,
    "read_timeout": 60000,
    "write_timeout": 60000,
    "retries": 3
  }' | jq .

echo "✅ Serviços registrados!"

# ─────────────────────────────────────────────────────────
# 2. REGISTRAR ROTAS
# ─────────────────────────────────────────────────────────

echo ""
echo "🛤️  Registrando rotas..."

# Rotas do Serviço de Produtos
curl -s -X POST "$KONG_ADMIN_URL/services/product-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "product-routes",
    "paths": ["/api/v1/products"],
    "strip_path": false,
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"]
  }' | jq .

# Rotas do Serviço de Pedidos
curl -s -X POST "$KONG_ADMIN_URL/services/order-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order-routes",
    "paths": ["/api/v1/orders"],
    "strip_path": false,
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"]
  }' | jq .

# Rotas do Serviço de Usuários
curl -s -X POST "$KONG_ADMIN_URL/services/user-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "user-routes",
    "paths": ["/api/v1/users"],
    "strip_path": false,
    "methods": ["GET", "POST", "PUT", "DELETE", "PATCH"]
  }' | jq .

# Rotas do Serviço de Notificações
curl -s -X POST "$KONG_ADMIN_URL/services/notification-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "notification-routes",
    "paths": ["/api/v1/notifications"],
    "strip_path": false,
    "methods": ["GET", "POST"]
  }' | jq .

echo "✅ Rotas registradas!"

# ─────────────────────────────────────────────────────────
# 3. CONFIGURAR PLUGINS GLOBAIS
# ─────────────────────────────────────────────────────────

echo ""
echo "🔌 Configurando plugins globais..."

# Rate Limiting Global (limitar requests por IP)
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting",
    "config": {
      "minute": 100,
      "hour": 5000,
      "policy": "redis",
      "redis_host": "redis",
      "redis_port": 6379,
      "redis_password": "your_redis_password_here",
      "redis_database": 1,
      "fault_tolerant": true,
      "hide_client_headers": false
    }
  }' | jq .

# CORS (Cross-Origin Resource Sharing)
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cors",
    "config": {
      "origins": ["http://localhost:3000", "http://localhost:4200"],
      "methods": ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"],
      "headers": ["Authorization", "Content-Type", "Accept", "X-Request-ID"],
      "exposed_headers": ["X-Auth-Token", "X-Request-ID"],
      "credentials": true,
      "max_age": 3600
    }
  }' | jq .

# Request Transformer (adicionar headers úteis)
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "correlation-id",
    "config": {
      "header_name": "X-Request-ID",
      "generator": "uuid#counter",
      "echo_downstream": true
    }
  }' | jq .

# Logging (File Log)
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "file-log",
    "config": {
      "path": "/tmp/kong-access.log",
      "reopen": true
    }
  }' | jq .

# Proxy Cache (Cache de respostas no Kong usando Redis)
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "proxy-cache",
    "config": {
      "strategy": "memory",
      "content_type": ["application/json"],
      "cache_ttl": 300,
      "cache_control": true,
      "response_code": [200, 301],
      "request_method": ["GET"],
      "memory": {
        "dictionary_name": "kong_db_cache"
      }
    }
  }' | jq .

# Response Transformer (adicionar headers de segurança)
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "response-transformer",
    "config": {
      "add": {
        "headers": [
          "X-Content-Type-Options:nosniff",
          "X-Frame-Options:DENY",
          "Strict-Transport-Security:max-age=31536000; includeSubDomains"
        ]
      }
    }
  }' | jq .

echo "✅ Plugins globais configurados!"

# ─────────────────────────────────────────────────────────
# 4. CONFIGURAR PLUGINS POR SERVIÇO
# ─────────────────────────────────────────────────────────

echo ""
echo "🔌 Configurando plugins por serviço..."

# Rate limiting mais restritivo para serviço de notificações
curl -s -X POST "$KONG_ADMIN_URL/services/notification-service/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting",
    "config": {
      "minute": 30,
      "hour": 500,
      "policy": "redis",
      "redis_host": "redis",
      "redis_port": 6379,
      "redis_password": "your_redis_password_here",
      "redis_database": 1,
      "fault_tolerant": true
    }
  }' | jq .

echo "✅ Plugins por serviço configurados!"

# ─────────────────────────────────────────────────────────
# 5. CONFIGURAR AUTENTICAÇÃO (JWT)
# ─────────────────────────────────────────────────────────

echo ""
echo "🔒 Configurando autenticação JWT..."

# Plugin JWT Global (todas as rotas exigem token)
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "jwt",
    "config": {
      "key_claim_name": "iss",
      "claims_to_verify": ["exp"],
      "header_names": ["Authorization"],
      "run_on_preflight": false
    }
  }' | jq .

# Criar consumidor padrão
curl -s -X POST "$KONG_ADMIN_URL/consumers" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "orchestrator-app",
    "custom_id": "orchestrator-main"
  }' | jq .

# Criar credenciais JWT para o consumidor
JWT_CREDENTIALS=$(curl -s -X POST "$KONG_ADMIN_URL/consumers/orchestrator-app/jwt" \
  -H "Content-Type: application/json" \
  -d '{
    "algorithm": "HS256",
    "key": "orchestrator-jwt-key",
    "secret": "your_jwt_secret_here_change_in_production"
  }')

echo "$JWT_CREDENTIALS" | jq .

echo "✅ Autenticação JWT configurada!"

# ─────────────────────────────────────────────────────────
# 6. HEALTH CHECK DAS ROTAS CONFIGURADAS
# ─────────────────────────────────────────────────────────

echo ""
echo "🏥 Verificando configuração..."
echo ""

echo "Serviços registrados:"
curl -s "$KONG_ADMIN_URL/services" | jq '.data[] | {name, host, port, path}'

echo ""
echo "Rotas registradas:"
curl -s "$KONG_ADMIN_URL/routes" | jq '.data[] | {name, paths, methods}'

echo ""
echo "Plugins ativos:"
curl -s "$KONG_ADMIN_URL/plugins" | jq '.data[] | {name, enabled, service}'

echo ""
echo "================================================"
echo "  ✅ Kong configurado com sucesso!"
echo "================================================"
echo ""
echo "  Proxy URL:    http://localhost:8000"
echo "  Admin API:    http://localhost:8001"
echo "  Kong Manager: http://localhost:8002"
echo "  Konga:        http://localhost:1337"
echo ""
```

Torne o script executável:

```bash
chmod +x scripts/kong/setup-kong.sh
```

### 3.3. Configuração Declarativa do Kong (Alternativa ao Script)

Para ambientes de CI/CD, é melhor usar configuração declarativa:

```yaml
# config/kong/kong.yml
_format_version: "3.0"
_transform: true

services:
  # ─── Product Service ─────────────────────────────────
  - name: product-service
    url: http://product-service:5001
    connect_timeout: 60000
    read_timeout: 60000
    write_timeout: 60000
    retries: 3
    routes:
      - name: product-routes
        paths:
          - /api/v1/products
        strip_path: false
        methods:
          - GET
          - POST
          - PUT
          - DELETE
          - PATCH

  # ─── Order Service ───────────────────────────────────
  - name: order-service
    url: http://order-service:5002
    connect_timeout: 60000
    read_timeout: 60000
    write_timeout: 60000
    retries: 3
    routes:
      - name: order-routes
        paths:
          - /api/v1/orders
        strip_path: false
        methods:
          - GET
          - POST
          - PUT
          - DELETE
          - PATCH

  # ─── User Service ────────────────────────────────────
  - name: user-service
    url: http://user-service:5003
    connect_timeout: 60000
    read_timeout: 60000
    write_timeout: 60000
    retries: 3
    routes:
      - name: user-routes
        paths:
          - /api/v1/users
        strip_path: false
        methods:
          - GET
          - POST
          - PUT
          - DELETE
          - PATCH

  # ─── Notification Service ────────────────────────────
  - name: notification-service
    url: http://notification-service:5004
    connect_timeout: 60000
    read_timeout: 60000
    write_timeout: 60000
    retries: 3
    routes:
      - name: notification-routes
        paths:
          - /api/v1/notifications
        strip_path: false
        methods:
          - GET
          - POST

plugins:
  # Rate Limiting Global
  - name: rate-limiting
    config:
      minute: 100
      hour: 5000
      policy: redis
      redis_host: redis
      redis_port: 6379
      redis_password: your_redis_password_here
      redis_database: 1
      fault_tolerant: true
      hide_client_headers: false

  # CORS
  - name: cors
    config:
      origins:
        - "http://localhost:3000"
        - "http://localhost:4200"
      methods:
        - GET
        - POST
        - PUT
        - DELETE
        - PATCH
        - OPTIONS
      headers:
        - Authorization
        - Content-Type
        - Accept
        - X-Request-ID
      credentials: true
      max_age: 3600

  # Correlation ID
  - name: correlation-id
    config:
      header_name: X-Request-ID
      generator: uuid#counter
      echo_downstream: true

  # Proxy Cache
  - name: proxy-cache
    config:
      strategy: memory
      content_type:
        - application/json
      cache_ttl: 300
      cache_control: true
      response_code:
        - 200
        - 301
      request_method:
        - GET

consumers:
  - username: orchestrator-app
    custom_id: orchestrator-main
```

Para usar a configuração declarativa, altere o serviço do Kong no `docker-compose.yml`:

```yaml
kong:
  image: kong:3.6
  container_name: orchestrator-kong
  environment:
    KONG_DATABASE: "off"
    KONG_DECLARATIVE_CONFIG: /etc/kong/kong.yml
    # ... outras variáveis ...
  volumes:
    - ./config/kong/kong.yml:/etc/kong/kong.yml
```

### 3.4. Kong com Rate Limiting Diferenciado por Consumer

```bash
# scripts/kong/setup-consumers.sh

KONG_ADMIN_URL="http://localhost:8001"

# Criar consumidores com diferentes níveis de acesso
# ─── Free Tier ──────────────────────────────────────────
curl -s -X POST "$KONG_ADMIN_URL/consumers" \
  -d "username=free-tier"

curl -s -X POST "$KONG_ADMIN_URL/consumers/free-tier/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting",
    "config": {
      "minute": 20,
      "hour": 500
    }
  }'

# Criar API Key para Free Tier
curl -s -X POST "$KONG_ADMIN_URL/consumers/free-tier/key-auth" \
  -d "key=free-tier-api-key-12345"

# ─── Premium Tier ───────────────────────────────────────
curl -s -X POST "$KONG_ADMIN_URL/consumers" \
  -d "username=premium-tier"

curl -s -X POST "$KONG_ADMIN_URL/consumers/premium-tier/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting",
    "config": {
      "minute": 1000,
      "hour": 50000
    }
  }'

curl -s -X POST "$KONG_ADMIN_URL/consumers/premium-tier/key-auth" \
  -d "key=premium-tier-api-key-67890"

# Habilitar Key Auth global
curl -s -X POST "$KONG_ADMIN_URL/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "key-auth",
    "config": {
      "key_names": ["apikey", "X-API-Key"],
      "key_in_header": true,
      "key_in_query": true,
      "hide_credentials": true
    }
  }'
```

---

## 4. Integração entre Redis, Kong e Microserviços

### 4.1. Docker Compose Completo

```yaml
# docker-compose.full.yml
version: '3.8'

services:
  # ═══════════════════════════════════════════════════════
  # INFRAESTRUTURA
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
      test: ["CMD", "redis-cli", "-a", "your_redis_password_here", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - orchestrator-network

  kong-database:
    image: postgres:15-alpine
    container_name: orchestrator-kong-db
    environment:
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong_password
      POSTGRES_DB: kong
    volumes:
      - kong_db_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U kong"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - orchestrator-network

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
      KONG_PG_PASSWORD: kong_password
    command: kong migrations bootstrap
    networks:
      - orchestrator-network

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
      KONG_PG_PASSWORD: kong_password
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
      KONG_PROXY_LISTEN: 0.0.0.0:8000, 0.0.0.0:8443 ssl
    ports:
      - "8000:8000"
      - "8443:8443"
      - "8001:8001"
      - "8002:8002"
    healthcheck:
      test: ["CMD", "kong", "health"]
      interval: 10s
      timeout: 10s
      retries: 10
    networks:
      - orchestrator-network

  # ═══════════════════════════════════════════════════════
  # MICROSERVIÇOS
  # ═══════════════════════════════════════════════════════

  product-service:
    build:
      context: ./src/Services/ProductService
      dockerfile: Dockerfile
    container_name: orchestrator-product-service
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ASPNETCORE_URLS=http://+:5001
      - Redis__ConnectionString=redis:6379,password=your_redis_password_here,abortConnect=false
      - Redis__InstanceName=ProductService:
    ports:
      - "5001:5001"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - orchestrator-network

  order-service:
    build:
      context: ./src/Services/OrderService
      dockerfile: Dockerfile
    container_name: orchestrator-order-service
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ASPNETCORE_URLS=http://+:5002
      - Redis__ConnectionString=redis:6379,password=your_redis_password_here,abortConnect=false
      - Redis__InstanceName=OrderService:
    ports:
      - "5002:5002"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - orchestrator-network

  user-service:
    build:
      context: ./src/Services/UserService
      dockerfile: Dockerfile
    container_name: orchestrator-user-service
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ASPNETCORE_URLS=http://+:5003
      - Redis__ConnectionString=redis:6379,password=your_redis_password_here,abortConnect=false
      - Redis__InstanceName=UserService:
    ports:
      - "5003:5003"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - orchestrator-network

  notification-service:
    build:
      context: ./src/Services/NotificationService
      dockerfile: Dockerfile
    container_name: orchestrator-notification-service
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - ASPNETCORE_URLS=http://+:5004
      - Redis__ConnectionString=redis:6379,password=your_redis_password_here,abortConnect=false
      - Redis__InstanceName=NotificationService:
    ports:
      - "5004:5004"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - orchestrator-network

  # ═══════════════════════════════════════════════════════
  # FERRAMENTAS
  # ═══════════════════════════════════════════════════════

  redis-commander:
    image: rediscommander/redis-commander:latest
    container_name: orchestrator-redis-commander
    environment:
      - REDIS_HOSTS=local:redis:6379:0:your_redis_password_here
    ports:
      - "8081:8081"
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - orchestrator-network

volumes:
  redis_data:
  kong_db_data:

networks:
  orchestrator-network:
    driver: bridge
```

### 4.2. Makefile para Comandos Simplificados

```makefile
# Makefile

.PHONY: help up down restart logs setup-kong redis-cli clean

COMPOSE_FILE = docker-compose.full.yml

help: ## Mostra esta mensagem de ajuda
    @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
        awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

up: ## Inicia todos os serviços
    docker compose -f $(COMPOSE_FILE) up -d
    @echo "Aguardando serviços iniciarem..."
    @sleep 15
    @echo "Executando setup do Kong..."
    @bash scripts/kong/setup-kong.sh

down: ## Para todos os serviços
    docker compose -f $(COMPOSE_FILE) down

restart: down up ## Reinicia todos os serviços

infra-up: ## Inicia apenas infraestrutura (Redis + Kong)
    docker compose -f $(COMPOSE_FILE) up -d redis kong-database kong-migration kong redis-commander

logs: ## Mostra logs de todos os serviços
    docker compose -f $(COMPOSE_FILE) logs -f

logs-kong: ## Mostra logs do Kong
    docker compose -f $(COMPOSE_FILE) logs -f kong

logs-redis: ## Mostra logs do Redis
    docker compose -f $(COMPOSE_FILE) logs -f redis

setup-kong: ## Configura rotas e plugins do Kong
    bash scripts/kong/setup-kong.sh

redis-cli: ## Abre CLI do Redis
    docker exec -it orchestrator-redis redis-cli -a your_redis_password_here

redis-monitor: ## Monitora comandos Redis em tempo real
    docker exec -it orchestrator-redis redis-cli -a your_redis_password_here MONITOR

redis-stats: ## Mostra estatísticas do Redis
    docker exec -it orchestrator-redis redis-cli -a your_redis_password_here INFO stats

kong-status: ## Mostra status do Kong
    @curl -s http://localhost:8001/status | jq .

kong-services: ## Lista serviços do Kong
    @curl -s http://localhost:8001/services | jq '.data[] | {name, host, port}'

kong-routes: ## Lista rotas do Kong
    @curl -s http://localhost:8001/routes | jq '.data[] | {name, paths, methods}'

kong-plugins: ## Lista plugins do Kong
    @curl -s http://localhost:8001/plugins | jq '.data[] | {name, enabled}'

clean: ## Remove volumes e dados persistidos
    docker compose -f $(COMPOSE_FILE) down -v
    @echo "Volumes removidos!"

test-product: ## Testa rota de produtos via Kong
    @echo "GET /api/v1/products via Kong Gateway:"
    @curl -s -w "\nHTTP Status: %{http_code}\nTempo: %{time_total}s\n" \
        http://localhost:8000/api/v1/products | head -20

test-cache: ## Testa cache (faz duas requisições e compara tempo)
    @echo "=== Primeira requisição (cache miss) ==="
    @curl -s -o /dev/null -w "Tempo: %{time_total}s\n" http://localhost:8000/api/v1/products
    @echo "=== Segunda requisição (cache hit) ==="
    @curl -s -o /dev/null -w "Tempo: %{time_total}s\n" http://localhost:8000/api/v1/products
```

---

## 5. Estratégias de Cache

### 5.1. Padrões de Cache Implementados

#### Cache-Aside (Lazy Loading) — **Recomendado para a maioria dos casos**

```
┌────────┐    1. GET    ┌───────────┐
│        │ ──────────►  │           │
│ Client │              │  Service  │
│        │ ◄──────────  │           │
└────────┘   5. Response └─────┬─────┘
                               │
                    2. GET ────►│◄──── 4. SET
                               │
                         ┌─────▼─────┐
                         │   Redis   │
                         │   Cache   │
                         └─────┬─────┘
                               │
                    3. DB Query │ (somente se cache miss)
                               │
                         ┌─────▼─────┐
                         │ Database  │
                         └───────────┘
```

**Já implementado no `GetOrSetAsync` do `RedisCacheService`.**

#### Write-Through — **Para dados críticos que precisam estar sempre atualizados**

```csharp
// Exemplo: Write-Through Pattern
public async Task<ProductDto> CreateAsync(CreateProductCommand cmd, CancellationToken ct)
{
    // 1. Escreve no banco
    var product = new Product(cmd.Name, cmd.Price);
    await _repository.AddAsync(product, ct);
    
    // 2. Imediatamente escreve no cache
    var dto = MapToDto(product);
    var key = CacheKeyHelper.ForEntity("product", "product", product.Id.ToString());
    await _cacheService.SetAsync(key, dto, TimeSpan.FromMinutes(30), ct);
    
    // 3. Invalida listas relacionadas
    await _cacheService.RemoveByPatternAsync("product:product:list");
    
    return dto;
}
```

#### Write-Behind (Write-Back) — **Para alta throughput de escrita**

```csharp
// Exemplo: Write-Behind com background job
public class WriteBehindCacheService
{
    private readonly Channel<CacheWriteOperation> _writeChannel;
    
    public WriteBehindCacheService()
    {
        _writeChannel = Channel.CreateBounded<CacheWriteOperation>(
            new BoundedChannelOptions(1000)
            {
                FullMode = BoundedChannelFullMode.Wait
            });
        
        // Background task que processa as escritas
        _ = ProcessWritesAsync();
    }

    public async Task WriteAsync<T>(string key, T value)
    {
        // Escreve no cache imediatamente
        await _cacheService.SetAsync(key, value);
        
        // Enfileira escrita no banco para processamento assíncrono
        await _writeChannel.Writer.WriteAsync(new CacheWriteOperation
        {
            Key = key,
            Value = value,
            Timestamp = DateTime.UtcNow
        });
    }

    private async Task ProcessWritesAsync()
    {
        await foreach (var operation in _writeChannel.Reader.ReadAllAsync())
        {
            try
            {
                await _repository.SaveAsync(operation);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Erro no write-behind para key: {Key}", operation.Key);
                // Retry logic aqui
            }
        }
    }
}
```

### 5.2. Tabela de TTL (Time-To-Live) Recomendado por Tipo de Dado

| Tipo de Dado | TTL | Estratégia | Justificativa |
|---|---|---|---|
| Dados de configuração | 1 hora | Cache-Aside | Raramente mudam |
| Lista de produtos | 5 minutos | Cache-Aside | Atualizações moderadas |
| Detalhe de produto | 15 minutos | Write-Through | Leitura frequente |
| Dados de sessão | 30 minutos | Write-Through | Segurança |
| Dados de usuário | 10 minutos | Cache-Aside | Privacidade |
| Resultados de busca | 2 minutos | Cache-Aside | Precisam estar frescos |
| Contadores/Métricas | 30 segundos | Write-Behind | Alta frequência de escrita |
| Dados de pedido | 5 minutos | Cache-Aside + Invalidação | Consistência importante |

### 5.3. Invalidação de Cache

```csharp
// src/Shared/Services/CacheInvalidationService.cs
namespace Orchestrator.Shared.Services;

public class CacheInvalidationService : ICacheInvalidationService
{
    private readonly ICacheService _cacheService;
    private readonly ILogger<CacheInvalidationService> _logger;

    // Mapa de dependências: quando uma entidade muda, quais caches invalidar
    private static readonly Dictionary<string, string[]> InvalidationMap = new()
    {
        ["product"] = new[] { "product:*", "order:*:products", "search:products:*" },
        ["order"] = new[] { "order:*", "user:*:orders", "dashboard:*" },
        ["user"] = new[] { "user:*", "order:*:user" },
    };

    public CacheInvalidationService(
        ICacheService cacheService,
        ILogger<CacheInvalidationService> logger)
    {
        _cacheService = cacheService;
        _logger = logger;
    }

    /// <summary>
    /// Invalida todos os caches relacionados a uma entidade.
    /// </summary>
    public async Task InvalidateEntityAsync(string entityType, string? entityId = null)
    {
        _logger.LogInformation(
            "Invalidando cache para entidade: {EntityType}, Id: {EntityId}",
            entityType, entityId ?? "ALL");

        // Invalidar cache específico da entidade
        if (entityId is not null)
        {
            await _cacheService.RemoveAsync($"{entityType}:{entityId}");
        }

        // Invalidar caches dependentes
        if (InvalidationMap.TryGetValue(entityType, out var patterns))
        {
            foreach (var pattern in patterns)
            {
                await _cacheService.RemoveByPatternAsync(pattern);
            }
        }
    }

    /// <summary>
    /// Invalida todo o cache de um serviço.
    /// Use com cautela — pode causar thundering herd.
    /// </summary>
    public async Task InvalidateServiceAsync(string serviceName)
    {
        _logger.LogWarning("Invalidando TODO o cache do serviço: {ServiceName}", serviceName);
        await _cacheService.RemoveByPatternAsync($"{serviceName}:*");
    }
}
```

### 5.4. Proteção contra Cache Stampede (Thundering Herd)

```csharp
// src/Shared/Services/StampedeProtectedCacheService.cs
using System.Collections.Concurrent;

namespace Orchestrator.Shared.Services;

/// <summary>
/// Decorador que protege contra cache stampede usando locks distribuídos.
/// Quando o cache expira, apenas UMA request vai ao banco; 
/// as demais aguardam o resultado.
/// </summary>
public class StampedeProtectedCacheService : ICacheService
{
    private readonly ICacheService _innerCache;
    private readonly IConnectionMultiplexer _redis;
    private readonly ILogger<StampedeProtectedCacheService> _logger;
    
    // Lock local para evitar múltiplas threads no mesmo processo
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> _locks = new();

    public StampedeProtectedCacheService(
        ICacheService innerCache,
        IConnectionMultiplexer redis,
        ILogger<StampedeProtectedCacheService> logger)
    {
        _innerCache = innerCache;
        _redis = redis;
        _logger = logger;
    }

    public async Task<T?> GetOrSetAsync<T>(
        string key,
        Func<Task<T>> factory,
        TimeSpan? expiration = null,
        CancellationToken cancellationToken = default)
    {
        // Tentar obter do cache primeiro
        var cached = await _innerCache.GetAsync<T>(key, cancellationToken);
        if (cached is not null)
            return cached;

        // Cache miss - usar lock para evitar stampede
        var lockKey = $"lock:{key}";
        var semaphore = _locks.GetOrAdd(key, _ => new SemaphoreSlim(1, 1));

        await semaphore.WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
        try
        {
            // Double-check: outra thread pode ter preenchido o cache
            cached = await _innerCache.GetAsync<T>(key, cancellationToken);
            if (cached is not null)
                return cached;

            // Lock distribuído usando Redis (para múltiplas instâncias)
            var db = _redis.GetDatabase();
            var lockAcquired = await db.StringSetAsync(
                lockKey, 
                Environment.MachineName, 
                TimeSpan.FromSeconds(30), 
                When.NotExists);

            if (!lockAcquired)
            {
                // Outra instância está processando - aguardar
                _logger.LogDebug("Lock distribuído ocupado para {Key}, aguardando...", key);
                
                for (int i = 0; i < 50; i++) // max 5 segundos
                {
                    await Task.Delay(100, cancellationToken);
                    cached = await _innerCache.GetAsync<T>(key, cancellationToken);
                    if (cached is not null)
                        return cached;
                }

                // Timeout - buscar diretamente
                _logger.LogWarning("Timeout aguardando lock para {Key}, buscando direto", key);
            }

            try
            {
                var value = await factory();
                if (value is not null)
                {
                    await _innerCache.SetAsync(key, value, expiration, cancellationToken);
                }
                return value;
            }
            finally
            {
                await db.KeyDeleteAsync(lockKey);
            }
        }
        finally
        {
            semaphore.Release();
        }
    }

    // Delegar demais métodos ao inner cache
    public Task<T?> GetAsync<T>(string key, CancellationToken ct = default)
        => _innerCache.GetAsync<T>(key, ct);

    public Task SetAsync<T>(string key, T value, TimeSpan? exp = null, CancellationToken ct = default)
        => _innerCache.SetAsync(key, value, exp, ct);

    public Task RemoveAsync(string key, CancellationToken ct = default)
        => _innerCache.RemoveAsync(key, ct);

    public Task RemoveByPatternAsync(string pattern, CancellationToken ct = default)
        => _innerCache.RemoveByPatternAsync(pattern, ct);

    public Task<bool> ExistsAsync(string key, CancellationToken ct = default)
        => _innerCache.ExistsAsync(key, ct);
}
```

---

## 6. Monitoramento e Observabilidade

### 6.1. Health Check do Redis no Microserviço

```csharp
// src/Shared/HealthChecks/RedisHealthCheck.cs
using Microsoft.Extensions.Diagnostics.HealthChecks;
using StackExchange.Redis;

namespace Orchestrator.Shared.HealthChecks;

public class RedisHealthCheck : IHealthCheck
{
    private readonly IConnectionMultiplexer _redis;

    public RedisHealthCheck(IConnectionMultiplexer redis)
    {
        _redis = redis;
    }

    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            var db = _redis.GetDatabase();
            var latency = await db.PingAsync();

            var data = new Dictionary<string, object>
            {
                ["latency_ms"] = latency.TotalMilliseconds,
                ["connected_clients"] = _redis.GetServer(_redis.GetEndPoints().First())
                    .Info("clients").FirstOrDefault()?.ToString() ?? "N/A",
                ["is_connected"] = _redis.IsConnected
            };

            if (latency.TotalMilliseconds > 100)
            {
                return HealthCheckResult.Degraded(
                    $"Redis respondendo com latência alta: {latency.TotalMilliseconds}ms",
                    data: data);
            }

            return HealthCheckResult.Healthy(
                $"Redis OK. Latência: {latency.TotalMilliseconds}ms",
                data: data);
        }
        catch (Exception ex)
        {
            return HealthCheckResult.Unhealthy(
                "Redis não está acessível",
                exception: ex);
        }
    }
}
```

Registro no `Program.cs`:

```csharp
// Program.cs
builder.Services.AddHealthChecks()
    .AddCheck<RedisHealthCheck>("redis", tags: new[] { "cache", "infrastructure" });

// No pipeline
app.MapHealthChecks("/health", new HealthCheckOptions
{
    ResponseWriter = UIResponseWriter.WriteHealthCheckUIResponse
});
```

### 6.2. Métricas de Cache (Prometheus)

```csharp
// src/Shared/Metrics/CacheMetrics.cs
using System.Diagnostics;
using System.Diagnostics.Metrics;

namespace Orchestrator.Shared.Metrics;

public static class CacheMetrics
{
    private static readonly Meter Meter = new("Orchestrator.Cache", "1.0.0");

    public static readonly Counter<long> CacheHits = 
        Meter.CreateCounter<long>("cache_hits_total", "hits", "Total de cache hits");

    public static readonly Counter<long> CacheMisses = 
        Meter.CreateCounter<long>("cache_misses_total", "misses", "Total de cache misses");

    public static readonly Counter<long> CacheErrors = 
        Meter.CreateCounter<long>("cache_errors_total", "errors", "Total de erros de cache");

    public static readonly Histogram<double> CacheLatency = 
        Meter.CreateHistogram<double>("cache_operation_duration_ms", "ms", "Latência das operações de cache");

    public static double GetHitRate()
    {
        // Implementar baseado nos counters
        return 0; // placeholder
    }
}
```

### 6.3. Dashboard de URLs Importantes

| Serviço | URL | Descrição |
|---|---|---|
| Kong Proxy | `http://localhost:8000` | Ponto de entrada para todas as APIs |
| Kong Admin | `http://localhost:8001` | API de administração do Kong |
| Kong Manager | `http://localhost:8002` | Interface gráfica do Kong |
| Konga | `http://localhost:1337` | Dashboard alternativo do Kong |
| Redis Commander | `http://localhost:8081` | Interface gráfica do Redis |
| Product Service | `http://localhost:5001` | Acesso direto (debug) |
| Order Service | `http://localhost:5002` | Acesso direto (debug) |
| User Service | `http://localhost:5003` | Acesso direto (debug) |
| Notification Service | `http://localhost:5004` | Acesso direto (debug) |

---

## 7. Troubleshooting

### 7.1. Problemas Comuns com Redis

| Problema | Causa Provável | Solução |
|---|---|---|
| `Connection refused` | Redis não está rodando | `docker compose up redis` |
| `NOAUTH` | Senha não configurada | Verificar `redis.conf` e connection string |
| `OOM command not allowed` | Memória cheia | Verificar `maxmemory-policy` |
| Latência alta | Operações bloqueantes | Evitar `KEYS *` em produção, usar `SCAN` |
| Cache não invalida | Pattern incorreto | Verificar prefixo `InstanceName` |

### 7.2. Problemas Comuns com Kong

| Problema | Causa Provável | Solução |
|---|---|---|
| `502 Bad Gateway` | Serviço downstream indisponível | Verificar se o microserviço está rodando |
| `429 Too Many Requests` | Rate limit atingido | Ajustar configuração do rate-limiting |
| `404 Not Found` | Rota não configurada | `curl localhost:8001/routes` |
| Timeout | Serviço lento | Aumentar `read_timeout` no serviço |
| Migrations falham | DB não está pronto | Verificar health check do postgres |

### 7.3. Comandos Úteis de Debug

```bash
# ─── Redis ──────────────────────────────────────────────

# Verificar se Redis está respondendo
docker exec orchestrator-redis redis-cli -a your_redis_password_here PING

# Ver todas as chaves (APENAS EM DESENVOLVIMENTO!)
docker exec orchestrator-redis redis-cli -a your_redis_password_here KEYS "*"

# Ver informações de memória
docker exec orchestrator-redis redis-cli -a your_redis_password_here INFO memory

# Monitorar comandos em tempo real
docker exec orchestrator-redis redis-cli -a your_redis_password_here MONITOR

# Ver TTL de uma chave
docker exec orchestrator-redis redis-cli -a your_redis_password_here TTL "Orchestrator:product:product:123"

# Limpar todo o cache (CUIDADO!)
docker exec orchestrator-redis redis-cli -a your_redis_password_here FLUSHALL

# ─── Kong ───────────────────────────────────────────────

# Status geral
curl -s http://localhost:8001/status | jq .

# Listar todos os serviços
curl -s http://localhost:8001/services | jq '.data[] | {name, host, port}'

# Listar todas as rotas
curl -s http://localhost:8001/routes | jq '.data[] | {name, paths}'

# Listar plugins ativos
curl -s http://localhost:8001/plugins | jq '.data[] | {name, enabled, service}'

# Testar uma rota via Kong
curl -v http://localhost:8000/api/v1/products

# Ver headers de resposta (cache status)
curl -I http://localhost:8000/api/v1/products

# ─── Docker ─────────────────────────────────────────────

# Ver logs de todos os serviços
docker compose -f docker-compose.full.yml logs -f

# Ver uso de recursos
docker stats

# Reiniciar um serviço específico
docker compose -f docker-compose.full.yml restart kong
```

### 7.4. Checklist de Verificação Pós-Deploy

- [ ] Redis está respondendo ao PING
- [ ] Redis Commander está acessível em `localhost:8081`
- [ ] Kong Admin API responde em `localhost:8001/status`
- [ ] Todas as rotas estão registradas (`localhost:8001/routes`)
- [ ] Rate limiting está funcionando (testar com múltiplas requests)
- [ ] CORS está configurado corretamente
- [ ] Cache está sendo populado (verificar no Redis Commander)
- [ ] Cache está sendo invalidado em operações de escrita
- [ ] Health checks dos microserviços retornam `Healthy`
- [ ] Headers `X-Cache: HIT/MISS` estão presentes nas respostas
- [ ] Logs centralizados estão sendo gerados
- [ ] Métricas de cache hit/miss estão sendo coletadas

---

## Estrutura Final de Pastas

```
Orchestrator/
├── config/
│   ├── kong/
│   │   └── kong.yml                    # Config declarativa do Kong
│   └── redis/
│       └── redis.conf                  # Config do Redis
├── scripts/
│   └── kong/
│       ├── setup-kong.sh               # Setup imperativo do Kong
│       └── setup-consumers.sh          # Setup de consumers
├── src/
│   ├── Shared/
│   │   ├── Configuration/
│   │   │   └── RedisCacheSettings.cs
│   │   ├── Extensions/
│   │   │   └── CacheServiceExtensions.cs
│   │   ├── HealthChecks/
│   │   │   └── RedisHealthCheck.cs
│   │   ├── Helpers/
│   │   │   └── CacheKeyHelper.cs
│   │   ├── Interfaces/
│   │   │   ├── ICacheService.cs
│   │   │   └── ICacheInvalidationService.cs
│   │   ├── Metrics/
│   │   │   └── CacheMetrics.cs
│   │   ├── Middleware/
│   │   │   └── ResponseCacheMiddleware.cs
│   │   └── Services/
│   │       ├── RedisCacheService.cs
│   │       ├── StampedeProtectedCacheService.cs
│   │       └── CacheInvalidationService.cs
│   └── Services/
│       ├── ProductService/
│       ├── OrderService/
│       ├── UserService/
│       └── NotificationService/
├── docker-compose.yml                  # Compose simplificado
├── docker-compose.full.yml             # Compose completo
├── Makefile                            # Comandos simplificados
└── CACHE_AND_GATEWAY_IMPLEMENTATION.md # Este documento
```

---

## Ordem de Execução Recomendada

1. **Criar arquivos de configuração** (`redis.conf`, `kong.yml`)
2. **Subir infraestrutura**: `make infra-up`
3. **Implementar camada de cache** nos microserviços (NuGet packages, DI, Services)
4. **Testar cache isoladamente** (sem Kong)
5. **Configurar Kong**: `make setup-kong`
6. **Testar fluxo completo** via Kong Gateway
7. **Ajustar TTLs e rate limits** baseado em métricas reais
8. **Implementar monitoramento** (health checks, métricas)
9. **Documentar decisões** de TTL e invalidação por entidade