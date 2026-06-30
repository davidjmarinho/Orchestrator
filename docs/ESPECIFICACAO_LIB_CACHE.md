# Especificação Completa — RedisCache.Library

## Objetivo

Biblioteca .NET compartilhada entre **UsersAPI**, **PaymentAPI**, **NotificationsAPI** e **CatalogAPI** para cache distribuído com Redis. Este documento é a **fonte única de verdade** para implementação.

---

## 1. Estrutura de Pastas

```
RedisCache.Library/
├── RedisCache.Library.csproj
├── Configuration/
│   └── RedisCacheOptions.cs
├── Interfaces/
│   └── ICacheService.cs
├── Services/
│   └── RedisCacheService.cs
├── Serialization/
│   └── CacheSerializer.cs
└── Extensions/
    └── ServiceCollectionExtensions.cs
```

---

## 2. Arquivo de Projeto

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFrameworks>net6.0;net8.0</TargetFrameworks>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <RootNamespace>RedisCache.Library</RootNamespace>
    <AssemblyName>RedisCache.Library</AssemblyName>

    <!-- NuGet -->
    <PackageId>RedisCache.Library</PackageId>
    <Version>1.0.0</Version>
    <Authors>FCG Tech</Authors>
    <Description>Biblioteca de cache distribuído com Redis para APIs .NET</Description>
    <PackageTags>redis;cache;distributed-cache;dotnet</PackageTags>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="StackExchange.Redis" Version="2.8.16" />
    <PackageReference Include="System.Text.Json" Version="8.0.5" />
    <PackageReference Include="Microsoft.Extensions.DependencyInjection.Abstractions" Version="8.0.2" />
    <PackageReference Include="Microsoft.Extensions.Options" Version="8.0.2" />
    <PackageReference Include="Microsoft.Extensions.Logging.Abstractions" Version="8.0.2" />
  </ItemGroup>
</Project>
```

> **Importante:** usar `System.Text.Json` em vez de `Newtonsoft.Json` para alinhar com o padrão do .NET moderno.

---

## 3. Classe de Configuração

```csharp
// filepath: RedisCache.Library/Configuration/RedisCacheOptions.cs
namespace RedisCache.Library.Configuration;

public class RedisCacheOptions
{
    /// <summary>
    /// String de conexão do Redis. Ex: "localhost:6379" ou "redis:6379,password=123"
    /// </summary>
    public string ConnectionString { get; set; } = "localhost:6379";

    /// <summary>
    /// Prefixo adicionado a todas as chaves para isolar dados entre APIs.
    /// Ex: "users:", "payments:", "catalog:", "notifications:"
    /// </summary>
    public string KeyPrefix { get; set; } = string.Empty;

    /// <summary>
    /// Tempo de expiração padrão em minutos. Usado quando nenhum TTL é informado.
    /// </summary>
    public int DefaultExpirationInMinutes { get; set; } = 30;

    /// <summary>
    /// Habilita ou desabilita o cache globalmente (útil para testes).
    /// </summary>
    public bool Enabled { get; set; } = true;
}
```

---

## 4. Interface do Serviço de Cache

> **Padrão obrigatório:** todos os métodos são **assíncronos** e usam o sufixo `Async`.

```csharp
// filepath: RedisCache.Library/Interfaces/ICacheService.cs
namespace RedisCache.Library.Interfaces;

public interface ICacheService
{
    /// <summary>
    /// Obtém um valor do cache. Retorna default(T) se a chave não existir.
    /// </summary>
    Task<T?> GetAsync<T>(string key, CancellationToken ct = default);

    /// <summary>
    /// Armazena um valor no cache com expiração opcional.
    /// Se expiration for null, usa o DefaultExpirationInMinutes da configuração.
    /// </summary>
    Task SetAsync<T>(string key, T value, TimeSpan? expiration = null, CancellationToken ct = default);

    /// <summary>
    /// Remove uma chave do cache.
    /// </summary>
    Task RemoveAsync(string key, CancellationToken ct = default);

    /// <summary>
    /// Remove todas as chaves que começam com o padrão informado.
    /// Ex: RemoveByPrefixAsync("produto:") remove "produto:1", "produto:2", etc.
    /// </summary>
    Task RemoveByPrefixAsync(string prefixPattern, CancellationToken ct = default);

    /// <summary>
    /// Verifica se uma chave existe no cache.
    /// </summary>
    Task<bool> ExistsAsync(string key, CancellationToken ct = default);

    /// <summary>
    /// Obtém o valor do cache. Se não existir, executa a factory, armazena o resultado e retorna.
    /// </summary>
    Task<T?> GetOrSetAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null, CancellationToken ct = default);
}
```

---

## 5. Serialização

```csharp
// filepath: RedisCache.Library/Serialization/CacheSerializer.cs
using System.Text.Json;

namespace RedisCache.Library.Serialization;

internal static class CacheSerializer
{
    private static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = true,
        WriteIndented = false
    };

    public static string Serialize<T>(T value) => JsonSerializer.Serialize(value, Options);

    public static T? Deserialize<T>(string json) => JsonSerializer.Deserialize<T>(json, Options);
}
```

---

## 6. Implementação do Serviço

```csharp
// filepath: RedisCache.Library/Services/RedisCacheService.cs
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using RedisCache.Library.Configuration;
using RedisCache.Library.Interfaces;
using RedisCache.Library.Serialization;
using StackExchange.Redis;

namespace RedisCache.Library.Services;

public class RedisCacheService : ICacheService
{
    private readonly IDatabase _database;
    private readonly IConnectionMultiplexer _connection;
    private readonly RedisCacheOptions _options;
    private readonly ILogger<RedisCacheService> _logger;

    public RedisCacheService(
        IConnectionMultiplexer connection,
        IOptions<RedisCacheOptions> options,
        ILogger<RedisCacheService> logger)
    {
        _connection = connection;
        _database = connection.GetDatabase();
        _options = options.Value;
        _logger = logger;
    }

    private string BuildKey(string key) => string.IsNullOrEmpty(_options.KeyPrefix)
        ? key
        : $"{_options.KeyPrefix}{key}";

    private TimeSpan GetExpiration(TimeSpan? expiration) =>
        expiration ?? TimeSpan.FromMinutes(_options.DefaultExpirationInMinutes);

    public async Task<T?> GetAsync<T>(string key, CancellationToken ct = default)
    {
        if (!_options.Enabled) return default;

        try
        {
            var fullKey = BuildKey(key);
            var value = await _database.StringGetAsync(fullKey);

            if (value.IsNullOrEmpty)
            {
                _logger.LogDebug("Cache MISS para chave: {Key}", fullKey);
                return default;
            }

            _logger.LogDebug("Cache HIT para chave: {Key}", fullKey);
            return CacheSerializer.Deserialize<T>(value!);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao obter cache para chave: {Key}", key);
            return default; // Falha no cache não deve derrubar a aplicação
        }
    }

    public async Task SetAsync<T>(string key, T value, TimeSpan? expiration = null, CancellationToken ct = default)
    {
        if (!_options.Enabled) return;

        try
        {
            var fullKey = BuildKey(key);
            var json = CacheSerializer.Serialize(value);
            await _database.StringSetAsync(fullKey, json, GetExpiration(expiration));
            _logger.LogDebug("Cache SET para chave: {Key}", fullKey);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao definir cache para chave: {Key}", key);
        }
    }

    public async Task RemoveAsync(string key, CancellationToken ct = default)
    {
        if (!_options.Enabled) return;

        try
        {
            var fullKey = BuildKey(key);
            await _database.KeyDeleteAsync(fullKey);
            _logger.LogDebug("Cache REMOVE para chave: {Key}", fullKey);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao remover cache para chave: {Key}", key);
        }
    }

    public async Task RemoveByPrefixAsync(string prefixPattern, CancellationToken ct = default)
    {
        if (!_options.Enabled) return;

        try
        {
            var fullPrefix = BuildKey(prefixPattern);
            var endpoints = _connection.GetEndPoints();

            foreach (var endpoint in endpoints)
            {
                var server = _connection.GetServer(endpoint);
                var keys = server.Keys(pattern: $"{fullPrefix}*").ToArray();

                if (keys.Length > 0)
                {
                    await _database.KeyDeleteAsync(keys);
                    _logger.LogDebug("Cache REMOVE BY PREFIX: {Prefix} ({Count} chaves)", fullPrefix, keys.Length);
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao remover cache por prefixo: {Prefix}", prefixPattern);
        }
    }

    public async Task<bool> ExistsAsync(string key, CancellationToken ct = default)
    {
        if (!_options.Enabled) return false;

        try
        {
            return await _database.KeyExistsAsync(BuildKey(key));
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Erro ao verificar existência da chave: {Key}", key);
            return false;
        }
    }

    public async Task<T?> GetOrSetAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null, CancellationToken ct = default)
    {
        var cached = await GetAsync<T>(key, ct);
        if (cached is not null) return cached;

        var value = await factory();
        if (value is not null)
            await SetAsync(key, value, expiration, ct);

        return value;
    }
}
```

---

## 7. Extensão para Registro de Dependência

```csharp
// filepath: RedisCache.Library/Extensions/ServiceCollectionExtensions.cs
using Microsoft.Extensions.DependencyInjection;
using RedisCache.Library.Configuration;
using RedisCache.Library.Interfaces;
using RedisCache.Library.Services;
using StackExchange.Redis;

namespace RedisCache.Library.Extensions;

public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddRedisCache(
        this IServiceCollection services,
        Action<RedisCacheOptions> setupAction)
    {
        var options = new RedisCacheOptions();
        setupAction(options);

        // Registra as options via IOptions<T>
        services.Configure(setupAction);

        // Conexão singleton com o Redis
        services.AddSingleton<IConnectionMultiplexer>(_ =>
        {
            var configOptions = ConfigurationOptions.Parse(options.ConnectionString);
            configOptions.AbortOnConnectFail = false; // resiliência
            return ConnectionMultiplexer.Connect(configOptions);
        });

        // Serviço de cache como singleton (thread-safe)
        services.AddSingleton<ICacheService, RedisCacheService>();

        return services;
    }
}
```

---

## 8. Regras de Uso Obrigatórias para Todas as APIs

### 8.1 Registro no `Program.cs`

```csharp
using RedisCache.Library.Extensions;

builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("Redis")!;
    options.KeyPrefix = "users:";           // MUDAR POR API
    options.DefaultExpirationInMinutes = 30;
    options.Enabled = true;
});
```

| API | KeyPrefix |
|---|---|
| UsersAPI | `users:` |
| PaymentAPI | `payments:` |
| CatalogAPI | `catalog:` |
| NotificationsAPI | `notifications:` |

### 8.2 `appsettings.json`

```json
{
  "ConnectionStrings": {
    "Redis": "localhost:6379"
  }
}
```

### 8.3 Padrão de Chaves

```
{KeyPrefix}{entidade}:{identificador}
```

Exemplos:
- `users:user:123`
- `payments:pagamento:456`
- `catalog:produto:789`
- `notifications:config:email`

### 8.4 Exemplo de Uso com `GetOrSetAsync` (padrão recomendado)

```csharp
[HttpGet("{id}")]
public async Task<IActionResult> Get(int id)
{
    var resultado = await _cacheService.GetOrSetAsync(
        key: $"user:{id}",
        factory: () => _repository.GetByIdAsync(id),
        expiration: TimeSpan.FromMinutes(15));

    return resultado is not null ? Ok(resultado) : NotFound();
}
```

### 8.5 Invalidação de Cache em Operações de Escrita

```csharp
[HttpPut("{id}")]
public async Task<IActionResult> Update(int id, UpdateUserRequest request)
{
    await _repository.UpdateAsync(id, request);
    await _cacheService.RemoveAsync($"user:{id}");
    return NoContent();
}

[HttpDelete("{id}")]
public async Task<IActionResult> Delete(int id)
{
    await _repository.DeleteAsync(id);
    await _cacheService.RemoveAsync($"user:{id}");
    return NoContent();
}
```

---

## 9. Health Check (opcional mas recomendado)

Adicionar no `Program.cs` de cada API:

```csharp
builder.Services.AddHealthChecks()
    .AddRedis(builder.Configuration.GetConnectionString("Redis")!, name: "redis");
```

Requer o pacote:
```bash
dotnet add package AspNetCore.HealthChecks.Redis
```

---

## 10. Checklist de Validação

- [ ] Todos os métodos da interface são `async` com sufixo `Async`
- [ ] Propriedades de configuração: `ConnectionString`, `KeyPrefix`, `DefaultExpirationInMinutes`, `Enabled`
- [ ] Serialização usa `System.Text.Json`
- [ ] Erros de cache são logados mas **nunca propagados** (a API continua funcionando sem cache)
- [ ] `IConnectionMultiplexer` registrado como **Singleton**
- [ ] `ICacheService` registrado como **Singleton**
- [ ] Cada API usa um `KeyPrefix` único
- [ ] `AbortOnConnectFail = false` para resiliência
- [ ] Target framework: `net6.0;net8.0`