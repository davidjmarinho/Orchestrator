# CRIAÇÃO E IMPLEMENTAÇÃO DA BIBLIOTECA DE CACHE COM REDIS

## Introdução

Esta documentação descreve os passos necessários para criar e implementar uma biblioteca de cache utilizando Redis em um projeto .NET. A biblioteca foi projetada para otimizar as consultas ao banco de dados nas APIs de Pagamento, Notificações e Catálogo.

## Requisitos

Antes de começar, certifique-se de que você possui os seguintes requisitos:

- .NET SDK (versão 6.0 ou superior)
- Redis instalado e em execução (localmente ou em um servidor)
- Biblioteca StackExchange.Redis instalada no projeto

## Instalação do Redis

1. **Instalação Local**: Você pode instalar o Redis localmente seguindo as instruções disponíveis na [documentação oficial do Redis](https://redis.io/download).
2. **Uso de Docker**: Se preferir, você pode executar o Redis em um contêiner Docker com o seguinte comando:
   ```
   docker run --name redis -d -p 6379:6379 redis
   ```

## Configuração do Projeto

1. **Criar um novo projeto .NET**:
   ```
   dotnet new classlib -n RedisCache.Library
   cd RedisCache.Library
   ```

2. **Adicionar a biblioteca StackExchange.Redis**:
   ```
   dotnet add package StackExchange.Redis
   ```

3. **Estrutura do Projeto**: Organize o projeto conforme a estrutura abaixo:
   ```
   src
   ├── RedisCache.Library
   │   ├── Extensions
   │   ├── Interfaces
   │   ├── Services
   │   ├── Configuration
   │   └── RedisCache.Library.csproj
   ```

## Implementação da Biblioteca

### 1. Configuração das Opções do Redis

Crie a classe `RedisCacheOptions.cs` na pasta `Configuration`:

```csharp
public class RedisCacheOptions
{
    public string ConnectionString { get; set; }
    public int ExpirationTimeInMinutes { get; set; }
}
```

### 2. Interface de Cache

Defina a interface `ICacheService.cs` na pasta `Interfaces`:

```csharp
public interface ICacheService
{
    Task<T> GetAsync<T>(string key);
    Task SetAsync<T>(string key, T value, TimeSpan? expiration = null);
    Task RemoveAsync(string key);
}
```

### 3. Implementação do Serviço de Cache

Implemente a classe `RedisCacheService.cs` na pasta `Services`:

```csharp
public class RedisCacheService : ICacheService
{
    private readonly IDatabase _database;

    public RedisCacheService(IConnectionMultiplexer connectionMultiplexer)
    {
        _database = connectionMultiplexer.GetDatabase();
    }

    public async Task<T> GetAsync<T>(string key)
    {
        var value = await _database.StringGetAsync(key);
        return value.IsNull ? default : JsonConvert.DeserializeObject<T>(value);
    }

    public async Task SetAsync<T>(string key, T value, TimeSpan? expiration = null)
    {
        var jsonValue = JsonConvert.SerializeObject(value);
        await _database.StringSetAsync(key, jsonValue, expiration);
    }

    public async Task RemoveAsync(string key)
    {
        await _database.KeyDeleteAsync(key);
    }
}
```

### 4. Extensões para Injeção de Dependência

Adicione o método de extensão `AddRedisCache` em `ServiceCollectionExtensions.cs`:

```csharp
public static class ServiceCollectionExtensions
{
    public static IServiceCollection AddRedisCache(this IServiceCollection services, Action<RedisCacheOptions> setupAction)
    {
        var options = new RedisCacheOptions();
        setupAction(options);

        services.AddSingleton<IConnectionMultiplexer>(ConnectionMultiplexer.Connect(options.ConnectionString));
        services.AddScoped<ICacheService, RedisCacheService>();

        return services;
    }
}
```

## Conclusão

Após seguir os passos acima, você terá uma biblioteca de cache funcional utilizando Redis. A próxima etapa é integrar essa biblioteca nas suas APIs de Pagamento, Notificações e Catálogo, o que será detalhado no arquivo `UTILIZACAO_NAS_APIS.md`.