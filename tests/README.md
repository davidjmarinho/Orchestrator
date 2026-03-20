# 🎯 Orchestrator - Event-Driven Microservices Orchestration

## 📋 Índice
- [Visão Geral](#-visão-geral)
- [Arquitetura](#-arquitetura)
- [Como Funciona](#-como-funciona)
- [Executando o Orchestrator](#-executando-o-orchestrator)
- [Integração com Microserviços](#-integração-com-microserviços)
- [Eventos Suportados](#-eventos-suportados)
- [Testes](#-testes)
- [Troubleshooting](#-troubleshooting)

---

## 🔍 Visão Geral

O **Orchestrator** é um serviço centralizado responsável por coordenar a comunicação entre microserviços através de eventos assíncronos. Ele atua como um mediador que:

- 📨 Consome eventos de diferentes microserviços via **RabbitMQ**
- 🔄 Orquestra fluxos de negócio complexos
- 📤 Publica novos eventos para outros serviços
- 💾 Registra todos os eventos processados no **MongoDB** para auditoria

### 🏗️ Stack Tecnológica

| Componente | Tecnologia | Versão |
|------------|-----------|--------|
| Runtime | .NET | 8.0 |
| Message Broker | RabbitMQ | 3.x |
| Database | MongoDB | 4.4 |
| Container | Docker | - |
| Orchestration | Kubernetes | - |

---

## 🏛️ Arquitetura

```
┌─────────────────┐       ┌─────────────────┐       ┌─────────────────┐
│   Users API     │       │   Orders API    │       │  Payments API   │
└────────┬────────┘       └────────┬────────┘       └────────┬────────┘
         │                         │                         │
         │ UserCreatedEvent        │ OrderPlacedEvent        │ PaymentProcessedEvent
         │                         │                         │
         └─────────────────────────┼─────────────────────────┘
                                   │
                            ┌──────▼──────┐
                            │  RabbitMQ   │
                            └──────┬──────┘
                                   │
                            ┌──────▼──────────┐
                            │ ORCHESTRATOR    │
                            │  - Consume      │
                            │  - Orchestrate  │
                            │  - Publish      │
                            │  - Log          │
                            └──────┬──────────┘
                                   │
                    ┌──────────────┼──────────────┐
                    │                             │
             ┌──────▼──────┐              ┌──────▼──────┐
             │   MongoDB   │              │  RabbitMQ   │
             │   (Logs)    │              │ (New Events)│
             └─────────────┘              └──────┬──────┘
                                                 │
                        ┌────────────────────────┼────────────────────────┐
                        │                        │                        │
                 ┌──────▼──────┐        ┌───────▼───────┐       ┌────────▼────────┐
                 │Notification │        │  Catalog API  │       │  Payment API    │
                 │    API      │        │               │       │                 │
                 └─────────────┘        └───────────────┘       └─────────────────┘
```

---

## ⚙️ Como Funciona

### 1️⃣ Fluxo de Criação de Usuário

```csharp
// Users API publica evento
var userCreatedEvent = new UserCreatedEvent
{
    UserId = "user-123",
    Email = "user@example.com",
    CreatedAt = DateTime.UtcNow
};

await messageBus.PublishAsync("user.created", userCreatedEvent);
```

**O que o Orchestrator faz:**
1. ✅ Consome o evento da fila `user.created`
2. 💾 Salva log com status `RECEIVED` no MongoDB
3. 📤 Publica `NotificationEvent` para enviar email de boas-vindas
4. 💾 Salva log com status `PROCESSED` no MongoDB

---

### 2️⃣ Fluxo de Pedido Realizado

```csharp
// Orders API publica evento
var orderPlacedEvent = new OrderPlacedEvent
{
    OrderId = "order-456",
    UserId = "user-123",
    TotalAmount = 599.99m,
    PlacedAt = DateTime.UtcNow
};

await messageBus.PublishAsync("order.placed", orderPlacedEvent);
```

**O que o Orchestrator faz:**
1. ✅ Consome o evento da fila `order.placed`
2. 💾 Registra recebimento no MongoDB
3. 📤 Publica `PaymentRequestEvent` para processar pagamento
4. 💾 Registra processamento no MongoDB

---

### 3️⃣ Fluxo de Pagamento Processado

```csharp
// Payments API publica evento
var paymentProcessedEvent = new PaymentProcessedEvent
{
    PaymentId = "pay-789",
    OrderId = "order-456",
    ProductId = "prod-111",
    UserId = "user-123",
    IsSuccessful = true,
    ProcessedAt = DateTime.UtcNow
};

await messageBus.PublishAsync("payment.processed", paymentProcessedEvent);
```

**O que o Orchestrator faz:**
1. ✅ Consome o evento da fila `payment.processed`
2. 💾 Registra recebimento
3. 📤 Publica `CatalogUpdateEvent` (atualizar estoque)
4. 📤 Publica `NotificationEvent` (confirmar pagamento)
5. 💾 Registra processamento

---

## 🚀 Executando o Orchestrator

### 🐳 Docker Compose

```bash
# 1. Subir infraestrutura
docker-compose up -d

# 2. Verificar status
docker-compose ps

# 3. Ver logs
docker-compose logs -f orchestrator
```

### ☸️ Kubernetes

```bash
# 1. Aplicar configurações
kubectl apply -f k8s/

# 2. Verificar pods
kubectl get pods -l app=orchestrator

# 3. Ver logs
kubectl logs -f deployment/orchestrator

# 4. Acessar RabbitMQ Management
kubectl port-forward svc/rabbitmq 15672:15672
# Acesse: http://localhost:15672 (admin/admin123)

# 5. Acessar MongoDB
kubectl port-forward svc/mongodb 27017:27017
# Conecte com: mongodb://admin:mongo%40123@localhost:27017/orchestrator
```

### 🛠️ Desenvolvimento Local

```bash
# 1. Configurar variáveis de ambiente
export RABBITMQ_HOST=localhost
export RABBITMQ_PORT=5672
export RABBITMQ_USER=admin
export RABBITMQ_PASS=admin123
export MONGO_HOST=localhost
export MONGO_PORT=27017
export MONGO_DB=orchestrator
export MONGO_USER=admin
export MONGO_PASS=mongo@123

# 2. Executar
dotnet run --project src/Orchestrator.Worker.csproj
```

---

## 🔌 Integração com Microserviços

### 📦 Instalando o SDK (NuGet)

```bash
dotnet add package RabbitMQ.Client
```

### 🔧 Configurando RabbitMQ na API

```csharp
// Program.cs ou Startup.cs
builder.Services.AddSingleton<IMessageBus>(provider =>
{
    var factory = new ConnectionFactory
    {
        HostName = Environment.GetEnvironmentVariable("RABBITMQ_HOST") ?? "localhost",
        Port = int.Parse(Environment.GetEnvironmentVariable("RABBITMQ_PORT") ?? "5672"),
        UserName = Environment.GetEnvironmentVariable("RABBITMQ_USER") ?? "guest",
        Password = Environment.GetEnvironmentVariable("RABBITMQ_PASS") ?? "guest"
    };
    return new RabbitMqPublisher(factory);
});
```

### 📤 Publicando Eventos

#### Exemplo 1: Users API - Criar Usuário

```csharp
[ApiController]
[Route("api/[controller]")]
public class UsersController : ControllerBase
{
    private readonly IMessageBus _messageBus;
    private readonly IUserRepository _userRepository;

    public UsersController(IMessageBus messageBus, IUserRepository userRepository)
    {
        _messageBus = messageBus;
        _userRepository = userRepository;
    }

    [HttpPost]
    public async Task<IActionResult> CreateUser([FromBody] CreateUserRequest request)
    {
        // 1. Criar usuário no banco
        var user = await _userRepository.CreateAsync(request);

        // 2. Publicar evento para o Orchestrator
        var userCreatedEvent = new UserCreatedEvent
        {
            UserId = user.Id,
            Email = user.Email,
            CreatedAt = DateTime.UtcNow
        };

        await _messageBus.PublishAsync("user.created", userCreatedEvent);

        // 3. Retornar resposta
        return CreatedAtAction(nameof(GetUser), new { id = user.Id }, user);
    }
}
```

#### Exemplo 2: Orders API - Criar Pedido

```csharp
[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    private readonly IMessageBus _messageBus;
    private readonly IOrderRepository _orderRepository;

    [HttpPost]
    public async Task<IActionResult> PlaceOrder([FromBody] PlaceOrderRequest request)
    {
        // 1. Salvar pedido
        var order = await _orderRepository.CreateAsync(request);

        // 2. Publicar evento
        var orderPlacedEvent = new OrderPlacedEvent
        {
            OrderId = order.Id,
            UserId = request.UserId,
            TotalAmount = order.TotalAmount,
            PlacedAt = DateTime.UtcNow
        };

        await _messageBus.PublishAsync("order.placed", orderPlacedEvent);

        return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
    }
}
```

#### Exemplo 3: Payments API - Processar Pagamento

```csharp
[ApiController]
[Route("api/[controller]")]
public class PaymentsController : ControllerBase
{
    private readonly IMessageBus _messageBus;
    private readonly IPaymentService _paymentService;

    [HttpPost("process")]
    public async Task<IActionResult> ProcessPayment([FromBody] ProcessPaymentRequest request)
    {
        // 1. Processar pagamento
        var payment = await _paymentService.ProcessAsync(request);

        // 2. Publicar evento
        var paymentProcessedEvent = new PaymentProcessedEvent
        {
            PaymentId = payment.Id,
            OrderId = request.OrderId,
            ProductId = request.ProductId,
            UserId = request.UserId,
            IsSuccessful = payment.Status == PaymentStatus.Approved,
            ProcessedAt = DateTime.UtcNow
        };

        await _messageBus.PublishAsync("payment.processed", paymentProcessedEvent);

        return Ok(payment);
    }
}
```

---

## 📋 Eventos Suportados

### 1. UserCreatedEvent
```csharp
public class UserCreatedEvent
{
    public string UserId { get; set; }
    public string Email { get; set; }
    public DateTime CreatedAt { get; set; }
}
```
**Fila:** `user.created`  
**Ação:** Publica `NotificationEvent` (email de boas-vindas)

---

### 2. OrderPlacedEvent
```csharp
public class OrderPlacedEvent
{
    public string OrderId { get; set; }
    public string UserId { get; set; }
    public decimal TotalAmount { get; set; }
    public DateTime PlacedAt { get; set; }
}
```
**Fila:** `order.placed`  
**Ação:** Publica `PaymentRequestEvent`

---

### 3. PaymentProcessedEvent
```csharp
public class PaymentProcessedEvent
{
    public string PaymentId { get; set; }
    public string OrderId { get; set; }
    public string ProductId { get; set; }
    public string UserId { get; set; }
    public bool IsSuccessful { get; set; }
    public DateTime ProcessedAt { get; set; }
}
```
**Fila:** `payment.processed`  
**Ação:** Publica `CatalogUpdateEvent` + `NotificationEvent`

---

## 🧪 Testes

### Executar Todos os Testes
```bash
dotnet test
```

### Cobertura de Testes
- ✅ **10 testes unitários** (Application layer)
- ✅ **7 testes de integração** (MongoDB + Fluxos completos)
- 📊 **Total: 17 testes** - Todos passando

---

## 🔍 Monitoramento

### Ver Logs no MongoDB

```bash
# 1. Port-forward
kubectl port-forward svc/mongodb 27017:27017

# 2. Conectar (Studio 3T ou MongoDB Compass)
mongodb://admin:mongo%40123@localhost:27017/orchestrator?authSource=admin

# 3. Consultar logs
db.Logs.find().sort({CreatedAt: -1}).limit(10)
```

### Estatísticas
```javascript
// Total de eventos processados
db.Logs.count()

// Eventos por status
db.Logs.aggregate([
  { $group: { _id: "$Status", count: { $sum: 1 } } }
])

// Eventos por tipo
db.Logs.aggregate([
  { $group: { _id: "$EventName", count: { $sum: 1 } } }
])
```

---

## 🐛 Troubleshooting

### ❌ Orchestrator não está consumindo mensagens

**Verificar:**
```bash
# 1. RabbitMQ está acessível?
kubectl exec deployment/orchestrator -- ping rabbitmq -c 3

# 2. Credenciais corretas?
kubectl get secret rabbitmq-secret -o yaml

# 3. Filas existem?
curl -u admin:admin123 http://localhost:15672/api/queues
```

---

### ❌ Erro de autenticação no MongoDB

**Solução:**
```bash
# Verificar credenciais
kubectl get secret mongodb-secret -o jsonpath='{.data.username}' | base64 -d
kubectl get secret mongodb-secret -o jsonpath='{.data.password}' | base64 -d

# Recriar pod
kubectl delete pod -l app=orchestrator
```

---

### ❌ Eventos não aparecem no MongoDB

**Verificar logs:**
```bash
kubectl logs deployment/orchestrator --tail=50
```

**Testar publicação manual:**
```bash
# Port-forward RabbitMQ
kubectl port-forward svc/rabbitmq 15672:15672

# Publicar evento de teste
curl -u admin:admin123 -X POST \
  http://localhost:15672/api/exchanges/%2F/amq.default/publish \
  -H 'Content-Type: application/json' \
  -d '{
    "routing_key": "order.placed",
    "payload": "{\"OrderId\":\"test-123\"}",
    "properties": {"delivery_mode": 2}
  }'
```
