# Utilização da Biblioteca de Cache nas APIs

Este documento fornece um guia detalhado sobre como implementar a biblioteca de cache usando Redis nas APIs de Pagamento, Notificações e Catálogo. A utilização do cache pode otimizar as consultas ao banco de dados, melhorando a performance e a escalabilidade das aplicações.

## Pré-requisitos

Antes de começar, certifique-se de que:

- A biblioteca de cache foi adicionada ao seu projeto conforme descrito no documento [CRIACAO_E_IMPLEMENTACAO.md](CRIACAO_E_IMPLEMENTACAO.md).
- O Redis está instalado e em execução em seu ambiente.

## Passo a Passo para Implementação

### 1. Registro do Serviço de Cache

Em cada uma das APIs, você deve registrar o serviço de cache no contêiner de injeção de dependência. Isso geralmente é feito no arquivo `Startup.cs` ou `Program.cs`, dependendo da versão do .NET que você está utilizando.

```csharp
public void ConfigureServices(IServiceCollection services)
{
    services.AddRedisCache(options =>
    {
        options.Configuration = "localhost:6379"; // Substitua pela sua string de conexão
        options.InstanceName = "SampleInstance"; // Nome da instância do Redis
    });

    // Outros serviços
}
```

### 2. Injeção do Serviço de Cache

Após registrar o serviço, você pode injetá-lo nas classes onde deseja utilizá-lo. Por exemplo, em um controlador de API:

```csharp
public class PagamentoController : ControllerBase
{
    private readonly ICacheService _cacheService;

    public PagamentoController(ICacheService cacheService)
    {
        _cacheService = cacheService;
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetPagamento(int id)
    {
        var cacheKey = $"pagamento_{id}";
        var pagamento = await _cacheService.Get<Pagamento>(cacheKey);

        if (pagamento == null)
        {
            // Simulação de consulta ao banco de dados
            pagamento = await _pagamentoRepository.GetByIdAsync(id);

            if (pagamento != null)
            {
                await _cacheService.Set(cacheKey, pagamento, TimeSpan.FromMinutes(30));
            }
        }

        return Ok(pagamento);
    }
}
```

### 3. Utilização em Outras APIs

O mesmo padrão pode ser seguido nas APIs de Notificações e Catálogo. Basta injetar o `ICacheService` e utilizar os métodos `Get`, `Set` e `Remove` conforme necessário.

### 4. Melhores Práticas

- **Defina chaves de cache únicas**: Utilize um padrão consistente para as chaves de cache, como prefixos que identifiquem a entidade e o ID.
- **Gerencie a expiração do cache**: Defina um tempo de expiração apropriado para os dados em cache, evitando que informações desatualizadas sejam servidas.
- **Evite o cache de dados sensíveis**: Não armazene informações sensíveis ou críticas no cache.

## Conclusão

A implementação da biblioteca de cache usando Redis nas suas APIs pode trazer melhorias significativas na performance. Siga as orientações acima para integrar o cache de forma eficaz e otimizar suas consultas ao banco de dados.