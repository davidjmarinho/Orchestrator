# Publicação e Uso da RedisCache.Library

Este documento explica como empacotar e publicar a biblioteca **RedisCache.Library** como um pacote NuGet e como consumi-la em suas APIs.

---

## 1. Preparar o projeto para publicação

O arquivo `RedisCache.Library.csproj` já contém as propriedades de pacote NuGet necessárias:

```xml
<PackageId>FCGLibCache</PackageId>
<Version>1.0.0</Version>
<Authors>FCG Tech</Authors>
<Description>Biblioteca de cache distribuído com Redis para APIs .NET</Description>
<PackageTags>redis;cache;distributed-cache;dotnet</PackageTags>
```

## 2. Gerar o pacote NuGet

Na raiz do projeto da biblioteca, execute:

```bash
cd src/RedisCache.Library
dotnet pack -c Release
```

O pacote `.nupkg` será gerado em `bin/Release/`.

## 3. Publicar o pacote

### Opção A — NuGet.org (público)

```bash
dotnet nuget push bin/Release/FCGLibCache.1.0.0.nupkg \
  --api-key SUA_API_KEY \
  --source https://api.nuget.org/v3/index.json
```

### Opção B — Feed privado (Azure Artifacts, GitHub Packages, etc.)

1. Adicione o feed como source:

```bash
dotnet nuget add source https://nuget.pkg.github.com/SEU_ORG/index.json \
  --name github \
  --username SEU_USUARIO \
  --password SEU_TOKEN
```

2. Publique:

```bash
dotnet nuget push bin/Release/FCGLibCache.1.0.0.nupkg \
  --source github
```

### Opção C — Pasta local (para testes)

```bash
mkdir -p ~/nuget-local
dotnet nuget push bin/Release/FCGLibCache.1.0.0.nupkg \
  --source ~/nuget-local

dotnet nuget add source ~/nuget-local --name local
```

---

## 4. Consumir a biblioteca na UsersAPI

### 4.1 Instalar o pacote

```bash
dotnet add package FCGLibCache
```

### 4.2 Configurar no `Program.cs`

```csharp
using RedisCache.Library.Extensions;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddRedisCache(options =>
{
    options.ConnectionString = builder.Configuration.GetConnectionString("Redis")!;
    options.KeyPrefix = "users:";              // Prefixo exclusivo da UsersAPI
    options.DefaultExpirationInMinutes = 30;
    options.Enabled = true;
});

builder.Services.AddControllers();

var app = builder.Build();
app.MapControllers();
app.Run();
```

### 4.3 `appsettings.json`

```json
{
  "ConnectionStrings": {
    "Redis": "localhost:6379"
  }
}
```

### 4.4 Prefixos por API

| API               | KeyPrefix        |
|-------------------|------------------|
| UsersAPI          | `users:`         |
| PaymentAPI        | `payments:`      |
| CatalogAPI        | `catalog:`       |
| NotificationsAPI  | `notifications:` |

### 4.5 Exemplo de uso — `UsersController`

```csharp
using Microsoft.AspNetCore.Mvc;
using RedisCache.Library.Interfaces;

[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly ICacheService _cache;
    private readonly IUserRepository _repo;

    public UsersController(ICacheService cache, IUserRepository repo)
    {
        _cache = cache;
        _repo = repo;
    }

    // GET — usa GetOrSetAsync (padrão recomendado)
    [HttpGet("{id}")]
    public async Task<IActionResult> Get(int id)
    {
        var user = await _cache.GetOrSetAsync(
            key: $"user:{id}",
            factory: () => _repo.GetByIdAsync(id),
            expiration: TimeSpan.FromMinutes(15));

        return user is not null ? Ok(user) : NotFound();
    }

    // PUT — invalida cache após escrita
    [HttpPut("{id}")]
    public async Task<IActionResult> Update(int id, UpdateUserRequest request)
    {
        await _repo.UpdateAsync(id, request);
        await _cache.RemoveAsync($"user:{id}");
        return NoContent();
    }

    // DELETE — invalida cache após exclusão
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(int id)
    {
        await _repo.DeleteAsync(id);
        await _cache.RemoveAsync($"user:{id}");
        return NoContent();
    }

    // Exemplo: limpar todo o cache de usuários
    [HttpPost("cache/clear")]
    public async Task<IActionResult> ClearCache()
    {
        await _cache.RemoveByPrefixAsync("user:");
        return NoContent();
    }
}
```

---

## 5. Referência dos métodos (`ICacheService`)

| Método | Descrição |
|---|---|
| `GetAsync<T>(key, ct)` | Retorna o valor do cache ou `default` se não existir |
| `SetAsync<T>(key, value, expiration?, ct)` | Armazena um valor com expiração opcional |
| `RemoveAsync(key, ct)` | Remove uma chave do cache |
| `RemoveByPrefixAsync(prefix, ct)` | Remove todas as chaves que começam com o prefixo |
| `ExistsAsync(key, ct)` | Verifica se a chave existe no cache |
| `GetOrSetAsync<T>(key, factory, expiration?, ct)` | Obtém do cache ou executa a factory e armazena |

---

## 6. Health Check (recomendado)

```csharp
builder.Services.AddHealthChecks()
    .AddRedis(builder.Configuration.GetConnectionString("Redis")!, name: "redis");
```

```bash
dotnet add package AspNetCore.HealthChecks.Redis
```
