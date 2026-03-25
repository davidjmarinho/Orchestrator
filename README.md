# 🎯 Orchestrator — Event-Driven Microservices

Orquestrador de eventos que coordena a comunicação entre microserviços via **RabbitMQ**, registrando tudo no **MongoDB**.

```
UserCreated ──►  Orchestrator ──► NotificationEvent (email boas-vindas)
OrderPlaced ──►  Orchestrator ──► PaymentRequestEvent (cobrar)
PaymentProcessed ► Orchestrator ► CatalogUpdateEvent + NotificationEvent
```

---

## 📋 Pré-requisitos

- **Docker Desktop** com Kubernetes habilitado
- **kubectl** configurado
- Imagens Docker publicadas no Docker Hub (`davidjmarinho/*`)

---

## 🚀 Como rodar tudo do zero

### 1. Deploy completo (um único comando)

```bash
bash k8s/deploy.sh --destroy
```

Esse comando faz **tudo automaticamente**:

| Etapa | O que faz |
|-------|-----------|
| 1 | Remove namespace anterior (se existir) |
| 2 | Cria namespace `fcg-tech-fase-2` |
| 3 | Aplica Secrets e ConfigMaps |
| 4 | Sobe MongoDB, PostgreSQL e SQL Server |
| 5 | Sobe RabbitMQ |
| 6 | Sobe Orchestrator |
| 7 | Sobe 4 microserviços (Users, Payments, Catalog, Notification) |
| 8 | Cria tabelas do Catalog API (Games, Orders, LibraryItems, MassTransit Outbox) |
| 9 | Configura bindings do RabbitMQ (UserCreated, OrderPlaced, PaymentProcessed) |
| 10 | Inicia port-forwards (8080-8083 + 15672) |

> ⏱️ Leva ~2 minutos. Ao final, 9 pods estarão Running.

### 2. Rodar o teste E2E

```bash
bash k8s/test-e2e.sh
```

O teste executa o fluxo completo automaticamente:

1. 👤 Registra um usuário novo (Users API)
2. 🔐 Atribui role Admin
3. 🔑 Faz login e obtém JWT
4. 🎮 Cadastra um jogo (Catalog API)
5. 🛒 Faz um pedido / compra o jogo
6. 📚 Verifica a biblioteca do usuário
7. ⏳ Aguarda propagação de eventos (8s)
8. 📜 Exibe logs de todos os microserviços
9. 🗄️ Mostra eventos registrados no MongoDB
10. 🐇 Lista filas do RabbitMQ

**Resultado esperado**: Todos os passos ✅ e 6 eventos no MongoDB (UserCreated, OrderPlaced, PaymentProcessed — cada um com RECEIVED + PROCESSED).

---

## 🧪 Testes unitários e de integração

```bash
dotnet test src/Orchestrator.Infrastructure.Tests
```

17 testes (10 unitários + 7 de integração) cobrindo:
- Handlers de eventos (UserCreated, OrderPlaced, PaymentProcessed)
- LogRepository com MongoDB (via Mongo2Go)
- RabbitMQ publisher

---

## 📦 Opções do deploy.sh

```bash
bash k8s/deploy.sh              # Deploy (cria o que falta)
bash k8s/deploy.sh --destroy    # Remove tudo e recria do zero
bash k8s/deploy.sh --delete     # Apenas remove tudo
bash k8s/deploy.sh --status     # Mostra status atual
```

---

## 🌐 Acessando os serviços

Os port-forwards são iniciados automaticamente pelo `deploy.sh`:

| Serviço | URL | Descrição |
|---------|-----|-----------|
| Users API | http://localhost:8080 | Registro e login |
| Payments API | http://localhost:8081 | Processamento de pagamentos |
| Catalog API | http://localhost:8082 | Catálogo de jogos, pedidos, biblioteca |
| Notification API | http://localhost:8083 | Envio de notificações |
| RabbitMQ UI | http://localhost:15672 | Management (admin / admin123) |

Se os port-forwards caírem, reinicie manualmente:

```bash
kubectl port-forward svc/users-api 8080:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/payments-api 8081:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/catalog-api 8082:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/notification-api 8083:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/rabbitmq 15672:15672 -n fcg-tech-fase-2 &
```

---

## 🏛️ Arquitetura

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌──────────────┐
│  Users API  │     │ Catalog API │     │Payments API │     │Notification  │
│  (8080)     │     │  (8082)     │     │  (8081)     │     │  API (8083)  │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘     └──────┬───────┘
       │                   │                   │                   │
       │ UserCreated       │ OrderPlaced       │ PaymentProcessed  │
       │                   │                   │                   │
       └───────────────────┴───────────────────┘                   │
                           │                                       │
                    ┌──────▼──────┐                                │
                    │  RabbitMQ   │◄────────────────────────────────┘
                    └──────┬──────┘        (consome eventos)
                           │
                    ┌──────▼──────────┐
                    │  ORCHESTRATOR   │
                    │   - Consome     │
                    │   - Orquestra   │
                    │   - Publica     │
                    │   - Loga        │
                    └──────┬──────────┘
                           │
              ┌────────────┼────────────┐
              │                         │
       ┌──────▼──────┐          ┌──────▼──────┐
       │   MongoDB   │          │  RabbitMQ   │
       │   (Logs)    │          │(Novos Events)│
       └─────────────┘          └─────────────┘
```

### Fluxo de Eventos

| Evento Recebido | Ação do Orchestrator | Evento Publicado |
|------------------|----------------------|------------------|
| `UserCreatedEvent` | Log + encaminha notificação | `NotificationEvent` |
| `OrderPlacedEvent` | Log + solicita pagamento | `PaymentRequestEvent` |
| `PaymentProcessedEvent` | Log + atualiza catálogo + notifica | `CatalogUpdateEvent` + `NotificationEvent` |

---

## 🗂️ Estrutura do Projeto

```
Orchestrator/
├── src/
│   ├── Program.cs                          # Entry point do Worker
│   ├── Orchestrator.Worker.csproj          # Projeto principal
│   ├── Orchestrator.Domain/                # Domínio (interfaces, eventos, entidades)
│   │   ├── IEventHandler.cs
│   │   ├── IMessageBus.cs
│   │   ├── ILogRepository.cs
│   │   ├── LogEntry.cs
│   │   └── Events/                         # Todos os eventos
│   ├── Orchestrator.Application/           # Handlers de eventos
│   │   ├── UserCreatedEventHandler.cs
│   │   ├── OrderPlacedEventHandler.cs
│   │   └── PaymentProcessedEventHandler.cs
│   └── Orchestrator.Infrastructure/        # Infraestrutura (RabbitMQ, MongoDB)
│       ├── RabbitMqConsumer.cs             # Consome 3 filas do RabbitMQ
│       ├── RabbitMqPublisher.cs            # Publica eventos
│       ├── LogRepository.cs               # Persiste logs no MongoDB
│       └── MongoDbContext.cs
├── k8s/                                    # Manifestos Kubernetes
│   ├── deploy.sh                           # 🚀 Script de deploy automatizado
│   ├── test-e2e.sh                         # 🧪 Teste E2E completo
│   ├── 00-namespace.yaml
│   ├── postgres-deployment.yaml            # PostgreSQL (3 databases)
│   ├── mongodb-deployment.yaml
│   ├── sqlserver-deployment.yaml           # SQL Server (Notification API)
│   ├── rabbitmq-deployment.yaml
│   ├── orchestrator-deployment.yaml
│   ├── users-api-deployment.yaml
│   ├── catalog-api-deployment.yaml
│   ├── payments-api-deployment.yaml
│   ├── notification-api-deployment.yaml
│   ├── init-catalog-tables.sql             # DDL do Catalog (Games, Outbox)
│   └── init-catalog-extra-tables.sql       # DDL do Catalog (Orders, Library)
├── tests/                                  # Testes unitários e integração
├── Dockerfile
├── docker-compose.yml
└── Orchestrator.sln
```

---

## 🗄️ Bancos de Dados

| Banco | Tecnologia | Serviço | Database |
|-------|-----------|---------|----------|
| PostgreSQL | postgres:15-alpine | Users API | `fcg_users_db` |
| PostgreSQL | postgres:15-alpine | Payments API | `fcg_payments_db` |
| PostgreSQL | postgres:15-alpine | Catalog API | `fcg_catalog_db` |
| SQL Server | Azure SQL Edge | Notification API | `fcg_notifications_db` |
| MongoDB | mongo:4.4 | Orchestrator | `orchestrator` |

---

## 🔍 Comandos úteis

```bash
# Status dos pods
kubectl get pods -n fcg-tech-fase-2

# Logs do Orchestrator
kubectl logs deployment/orchestrator -n fcg-tech-fase-2 --tail=30

# Logs do MongoDB (eventos registrados)
kubectl exec deployment/mongodb -n fcg-tech-fase-2 -- mongo orchestrator \
  --quiet --authenticationDatabase admin -u admin -p mongo@123 \
  --eval 'db.Logs.find().sort({CreatedAt:-1}).limit(5).forEach(function(d){printjson(d)})'

# Filas do RabbitMQ
kubectl exec deployment/rabbitmq -n fcg-tech-fase-2 -- \
  rabbitmqctl list_queues name messages consumers

# Reconstruir e deployar o Orchestrator
docker build -t davidjmarinho/orchestrator:v5 -f Dockerfile src/
docker push davidjmarinho/orchestrator:v5
kubectl set image deployment/orchestrator orchestrator=davidjmarinho/orchestrator:v5 -n fcg-tech-fase-2
```

---

## 🛠️ Stack Tecnológica

| Componente | Tecnologia |
|------------|-----------|
| Runtime | .NET 8.0 |
| Message Broker | RabbitMQ 3.x (com MassTransit) |
| Log Database | MongoDB 4.4 |
| API Databases | PostgreSQL 15 + SQL Server (Azure SQL Edge) |
| Containers | Docker |
| Orquestração | Kubernetes (Docker Desktop) |
| Testes | xUnit + Moq + Mongo2Go |
