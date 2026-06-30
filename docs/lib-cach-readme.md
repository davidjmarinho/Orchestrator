# 📦 FCGLibCache — Biblioteca de Cache Distribuído do FCG Games

> **NuGet Package:** `FCGLibCache` v1.0.1  
> **Runtime:** .NET 8.0  
> **Dependência Principal:** StackExchange.Redis 2.8.16  
> **Licença:** MIT

---

## 🎯 Objetivo

A **FCGLibCache** é a biblioteca compartilhada de cache distribuído do ecossistema **FCG Games**. Ela encapsula toda a comunicação com o **Redis**, oferecendo uma interface simples e resiliente (`ICacheService`) que é consumida por todos os microsserviços da plataforma.

### Por que ela existe?

| Problema | Solução |
|----------|---------|
| 🔄 Cada API implementava sua própria lógica de cache | Biblioteca centralizada com contrato único |
| ⚠️ Conexões Redis sem tratamento de falhas | Resiliência embutida — erros são capturados e logados, nunca propagados |
| 🔑 Chaves de cache sem padronização | Prefixo automático por serviço (`users:`, `catalog:`) |
| ⏱️ TTL inconsistente entre serviços | Expiração configurável com fallback padrão (30 min) |
| 🧪 Dificuldade para desabilitar cache em testes | Flag `Enabled` — desativa o cache sem mudar código |

---

## 🏗️ Arquitetura

```
┌─────────────────────────────────────────────────────┐
│                   FCGLibCache                       │
│                                                     │
│  ┌──────────────┐    ┌───────────────────────────┐  │
│  │ ICacheService │◄───│   RedisCacheService       │  │
│  │  (Interface)  │    │   (Implementação)         │  │
│  └──────────────┘    └──────────┬────────────────┘  │
│                                 │                    │
│  ┌──────────────────┐   ┌──────┴──────────────┐    │
│  │ RedisCacheOptions │   │  CacheSerializer    │    │
│  │  (Configuração)   │   │  (System.Text.Json) │    │
│  └──────────────────┘   └─────────────────────┘    │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  ServiceCollectionExtensions (.AddRedisCache) │   │
│  └──────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │  Redis 7    │
                    │  (Alpine)   │
                    └─────────────┘
```

---

## 📋 Interface `ICacheService`

A interface define **6 métodos assíncronos** que cobrem todas as operações de cache:

```csharp
public interface ICacheService
{
    // 🔍 Buscar valor do cache por chave
    Task<T?> GetAsync<T>(string key);

    // 💾 Armazenar valor no cache com TTL opcional
    Task SetAsync<T>(string key, T value, TimeSpan? expiration = null);

    // 🗑️ Remover uma chave específica do cache
    Task RemoveAsync(string key);

    // 🧹 Remover todas as chaves que começam com um prefixo
    Task RemoveByPrefixAsync(string prefix);

    // ❓ Verificar se uma chave existe no cache
    Task<bool> ExistsAsync(string key);

    // ⚡ Buscar do cache OU executar factory e gravar (Cache-Aside)
    Task<T?> GetOrSetAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null);
}
```

### Detalhamento dos Métodos

| Método | Descrição | Retorno em Falha |
|--------|-----------|------------------|
| `GetAsync<T>` | Deserializa o valor armazenado para o tipo `T` | `default(T)` |
| `SetAsync<T>` | Serializa com `CacheSerializer` e grava com TTL | Sem exceção |
| `RemoveAsync` | Remove exatamente uma chave (com prefixo) | Sem exceção |
| `RemoveByPrefixAsync` | Usa `SCAN` do Redis para encontrar e remover chaves por padrão | Sem exceção |
| `ExistsAsync` | Retorna `true/false` sem deserializar o valor | `false` |
| `GetOrSetAsync<T>` | Padrão Cache-Aside automático — retorna cache ou executa a factory | Resultado da factory |

---

## ⚙️ Configuração — `RedisCacheOptions`

```csharp
public class RedisCacheOptions
{
    public string ConnectionString { get; set; } = "localhost:6379";
    public string KeyPrefix { get; set; } = "";
    public int DefaultExpirationInMinutes { get; set; } = 30;
    public bool Enabled { get; set; } = true;
}
```

| Propriedade | Descrição | Padrão |
|-------------|-----------|--------|
| `ConnectionString` | String de conexão Redis (host:port,password=...) | `localhost:6379` |
| `KeyPrefix` | Prefixo adicionado automaticamente a todas as chaves | `""` |
| `DefaultExpirationInMinutes` | TTL padrão quando nenhuma expiração é informada | `30` |
| `Enabled` | Se `false`, todas as operações retornam imediatamente (no-op) | `true` |

---

## 🔌 Registro via Injeção de Dependência

A biblioteca fornece o extension method `AddRedisCache` para configuração com uma única linha:

```csharp
builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = "redis:6379,password=redis@123,abortConnect=false";
    options.KeyPrefix = "users:";
    options.DefaultExpirationInMinutes = 30;
    options.Enabled = true;
});
```

### O que o `AddRedisCache` registra internamente:

| Registro | Lifetime | Detalhe |
|----------|----------|---------|
| `RedisCacheOptions` | Singleton | Configurações informadas no Action |
| `ConnectionMultiplexer` | Singleton | Conexão Redis com `AbortOnConnectFail = false` |
| `ICacheService` → `RedisCacheService` | Singleton | Thread-safe, reutiliza a conexão |

---

## 🎮 Uso no FCG Games

### 🧑‍💼 UsersAPI (v2)

**Instalação:** `FCGLibCache 1.0.1` via NuGet  
**Prefixo:** `users:`  
**TTL:** 10 minutos (user by ID), 30 min (padrão)

```csharp
// Program.cs — Configuração
builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = redisConnectionString; // via env vars K8s
    options.KeyPrefix = "users:";
    options.DefaultExpirationInMinutes = 30;
    options.Enabled = true;
});

// UserEndpoints.cs — Busca de usuário com cache
group.MapGet("/{id:guid}", async (Guid id, UserManager<User> userManager, ICacheService cacheService) =>
{
    var cacheKey = $"user:{id}";
    var cachedUser = await cacheService.GetAsync<object>(cacheKey);

    if (cachedUser is not null)
    {
        AppMetrics.CacheHits.WithLabels("get_user").Inc();  // 📊 Prometheus
        return Results.Ok(cachedUser);
    }

    AppMetrics.CacheMisses.WithLabels("get_user").Inc();

    var user = await userManager.FindByIdAsync(id.ToString());
    if (user is null) return Results.NotFound();

    var userData = new { user.Id, user.Email, user.FullName };
    await cacheService.SetAsync(cacheKey, userData, TimeSpan.FromMinutes(10));
    return Results.Ok(userData);
});
```

> 📈 **Resultado em produção:** 84% cache hit rate em testes de carga (210 requests)

### 🕹️ CatalogAPI (v2)

**Instalação:** `FCGLibCache 1.0.1` via NuGet  
**Prefixo:** `catalog:`  
**TTL:** 5 minutos (listagem), 15 min (game by ID)

```csharp
// Program.cs — Configuração
builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = redisConnectionString;
    options.KeyPrefix = "catalog:";
    options.DefaultExpirationInMinutes = 60;
    options.Enabled = true;
});

// GamesEndpoints.cs — Listagem de jogos com cache
group.MapGet("/", async (ICacheService cacheService) =>
{
    var cacheKey = "games:all";
    var cached = await cacheService.GetAsync<List<GameDto>>(cacheKey);

    if (cached is not null)
    {
        AppMetrics.CacheHits.WithLabels("list_games").Inc();
        return Results.Ok(cached);
    }

    AppMetrics.CacheMisses.WithLabels("list_games").Inc();
    var games = _games.Values.ToList();
    await cacheService.SetAsync(cacheKey, games, TimeSpan.FromMinutes(5));
    return Results.Ok(games);
});
```

### 🔄 Padrão de Invalidação (CatalogAPI)

```csharp
// POST — Criar jogo → invalida listagem
await cacheService.RemoveAsync("games:all");

// PUT — Atualizar jogo → invalida item + listagem
await cacheService.RemoveAsync($"games:{id}");
await cacheService.RemoveAsync("games:all");

// DELETE — Remover jogo → invalida item + listagem
await cacheService.RemoveAsync($"games:{id}");
await cacheService.RemoveAsync("games:all");
```

---

## 🔑 Estratégia de Chaves no Redis

O `RedisCacheService` constrói chaves automaticamente com o formato:

```
{KeyPrefix}{key}
```

### Exemplos reais no cluster:

| Serviço | KeyPrefix | Chave Lógica | Chave no Redis |
|---------|-----------|-------------|----------------|
| UsersAPI | `users:` | `user:8059cbc4-...` | `users:user:8059cbc4-...` |
| CatalogAPI | `catalog:` | `games:all` | `catalog:games:all` |
| CatalogAPI | `catalog:` | `games:abc123` | `catalog:games:abc123` |

---

## 🛡️ Resiliência e Tratamento de Erros

A biblioteca foi projetada para **nunca derrubar a aplicação** por falha no Redis:

```
┌──────────┐     ┌─────────────────┐     ┌───────┐
│   API    │────▶│ RedisCacheService│────▶│ Redis │
│          │     │                  │     │       │
│          │◄────│  try/catch em    │◄────│       │
│          │     │  TODOS métodos   │     │       │
│          │     │                  │     │       │
│  continua│     │  Log.Warning()   │     │ FAIL  │
│  normal  │     │  return default  │     │  ✗    │
└──────────┘     └─────────────────┘     └───────┘
```

- ✅ Todas as operações estão dentro de `try/catch`
- ✅ Erros são logados via `ILogger<RedisCacheService>` (nível Warning)
- ✅ Retornos padrão: `default(T)` para Get, `false` para Exists
- ✅ A API continua respondendo normalmente — apenas sem cache
- ✅ Flag `Enabled = false` transforma todo o serviço em no-op

---

## 📊 Integração com Prometheus

As APIs que consomem a FCGLibCache expõem métricas de cache via **prometheus-net**:

| Métrica | Tipo | Labels | Descrição |
|---------|------|--------|-----------|
| `cache_hits_total` | Counter | `endpoint` | Requisições atendidas pelo cache |
| `cache_misses_total` | Counter | `endpoint` | Cache miss — acesso ao banco/fonte |
| `request_duration_seconds` | Histogram | `endpoint` | Tempo de resposta (cache vs banco) |

> 📉 As métricas são visualizadas no **Grafana** (dashboard com 12 painéis), incluindo gauge de Cache Hit Rate e gráfico de Hits vs Misses.

---

## 🐳 Infraestrutura Redis no Kubernetes

```yaml
# Redis 7 Alpine no namespace fcg-tech-fase-2
Image:    redis:7-alpine
Port:     6379
Password: redis@123 (via K8s Secret redis-secret)
Command:  redis-server --requirepass $(REDIS_PASSWORD)
```

As APIs recebem as credenciais via variáveis de ambiente:

```yaml
- name: REDIS_HOST
  value: "redis"
- name: REDIS_PORT
  value: "6379"
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: redis-secret
      key: redis-password
```

---

## 📐 Serialização

A classe `CacheSerializer` utiliza **System.Text.Json** com as seguintes configurações:

| Configuração | Valor |
|-------------|-------|
| PropertyNamingPolicy | `camelCase` |
| PropertyNameCaseInsensitive | `true` |

Isso garante compatibilidade com APIs que retornam JSON em camelCase (padrão ASP.NET Core).

---

## 📁 Estrutura do Projeto

```
RedisCache.Library/
├── 📄 RedisCache.Library.csproj     # PackageId=FCGLibCache, v1.0.1
├── 📂 Interfaces/
│   └── 📄 ICacheService.cs          # Contrato com 6 métodos
├── 📂 Services/
│   └── 📄 RedisCacheService.cs      # Implementação completa
├── 📂 Configuration/
│   └── 📄 RedisCacheOptions.cs      # 4 propriedades configuráveis
├── 📂 Extensions/
│   └── 📄 ServiceCollectionExtensions.cs  # AddRedisCache()
└── 📂 Serialization/
    └── 📄 CacheSerializer.cs        # System.Text.Json wrapper
```

---

## 🚀 Como Instalar

```bash
dotnet add package FCGLibCache --version 1.0.1
```

Ou no `.csproj`:

```xml
<PackageReference Include="FCGLibCache" Version="1.0.1" />
```

---

## 📝 Resumo

A **FCGLibCache** é o componente de infraestrutura que viabiliza o cache distribuído em toda a plataforma FCG Games. Com uma interface limpa de 6 métodos, resiliência total a falhas do Redis, prefixação automática de chaves e configuração por injeção de dependência, ela permite que qualquer microsserviço adicione cache Redis com **3 linhas de configuração** e zero risco de indisponibilidade por falha no cache.

| 📊 Métrica | Valor |
|-----------|-------|
| APIs integradas | 2 (UsersAPI, CatalogAPI) |
| Cache Hit Rate observado | ~84% |
| Métodos disponíveis | 6 |
| Overhead de integração | ~3 linhas de config |
| Versão atual | 1.0.1 |
| Target Framework | .NET 8.0 |
