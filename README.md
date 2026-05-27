# 🎯 Orchestrator — Event-Driven Microservices

Orquestrador de eventos que coordena a comunicação entre microserviços via **RabbitMQ**, registrando tudo no **MongoDB**. Inclui **Kong API Gateway** (JWT), **Redis Cache**, **Prometheus** e **Grafana** para observabilidade completa.

```
                        ┌──────────────┐
                        │ Kong Gateway │ ← JWT Auth + CORS + Rate Limiting
                        └──────┬───────┘
                               │
       ┌───────────────────────┼───────────────────────┐
       │                       │                       │
┌──────▼──────┐        ┌──────▼──────┐        ┌───────▼──────┐
│  Users API  │        │ Catalog API │        │ Payments API │
│  (v2+Cache) │        │ (v2+Cache)  │        │              │
└──────┬──────┘        └──────┬──────┘        └──────┬───────┘
       │                      │                      │
       └──────────────────────┼──────────────────────┘
                              │
                       ┌──────▼──────┐     ┌─────────────┐
                       │  RabbitMQ   │     │    Redis     │ ← Cache distribuído
                       └──────┬──────┘     └─────────────┘
                              │
                       ┌──────▼──────────┐
                       │  ORCHESTRATOR   │
                       └──────┬──────────┘
                              │
                ┌─────────────┼─────────────┐
                │                           │
         ┌──────▼──────┐            ┌──────▼──────┐
         │   MongoDB   │            │ Prometheus  │ → Grafana
         │   (Logs)    │            │  (Metrics)  │
         └─────────────┘            └─────────────┘
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
2. 🔐 Atribui role Admin via SQL
3. 🔑 Faz login e obtém JWT
4. 🎮 Cadastra um jogo no catálogo (Catalog API)
5. ⏳ Aguarda propagação de eventos via RabbitMQ
6. 📜 Exibe logs de todos os microserviços
7. 🗄️ Mostra eventos registrados no MongoDB
8. 🐇 Lista filas do RabbitMQ
9. 📊 Verifica targets do Prometheus
10. 📈 Verifica Grafana

**Resultado esperado**: Todos os passos ✅, eventos no MongoDB, Prometheus e Grafana acessíveis.

### 3. Teste de carga (Cache + Métricas)

```bash
bash k8s/test-load-users.sh
```

Gera **210 requests** para a UsersAPI com:
- 20 registros de usuários
- 20 logins
- 50 GETs (teste de cache hit/miss)
- 15 senhas erradas (401)
- 20 IDs inválidos (404)
- 10 requests sem token (401)
- 3 ondas de tráfego misto
- Verificação de métricas no Prometheus
- Verificação de chaves no Redis

**Resultado esperado**: ~84% cache hit rate, métricas no Prometheus.

### 4. Testar Kong via Postman

```bash
kubectl port-forward svc/kong-proxy 9080:80 -n fcg-tech-fase-2
```

Importe a collection `docs/postman-kong-collection.json` no Postman. Inclui:
- 20 requests organizadas em 7 pastas
- JWT gerado automaticamente (Pre-request Script)
- Testes automatizados (rotas públicas, protegidas, CORS, tokens inválidos)

---

## 🔐 Kong API Gateway

O Kong atua como porta de entrada única para todas as APIs.

| Configuração | Valor |
|-------------|-------|
| Proxy | `http://localhost:9080` (via port-forward) |
| JWT Algorithm | HS256 |
| JWT Issuer | `UsersAPI` |
| Consumer | `app-consumer` |
| CORS | Global (origins: *, headers: Authorization, Content-Type) |

### Rotas do Kong

| Rota | Auth | Backend |
|------|------|---------|
| `POST /api/users/register` | Pública | users-api |
| `POST /api/users/login` | Pública | users-api |
| `/api/users/*` | JWT obrigatório | users-api |
| `/api/catalog/*` | JWT obrigatório | catalog-api |
| `/api/products/*` | JWT obrigatório | catalog-api |

### Configurar o Kong

```bash
kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2
bash k8s/kong-setup.sh
```

---

## 📦 Redis Cache (FCGLibCache)

Cache distribuído via Redis usando a lib **FCGLibCache v1.0.1**.

| API | Prefixo | TTL | Chaves |
|-----|---------|-----|--------|
| UsersAPI | `users:` | 60 min | `users:user:{id}` |
| CatalogAPI | `catalog:` | 5-15 min | `catalog:games:all`, `catalog:games:{id}` |

Acessar o Redis:
```bash
kubectl port-forward svc/redis 6379:6379 -n fcg-tech-fase-2
# Another Redis Desktop Manager: host=127.0.0.1, port=6379, password=redis@123
```

---

## 📊 Observabilidade (Prometheus + Grafana)

### Prometheus
```bash
kubectl port-forward svc/prometheus 9090:9090 -n fcg-tech-fase-2
# Acesse: http://localhost:9090
```

Métricas coletadas:
- `http_requests_received_total` — total de requests por endpoint/método/status
- `http_request_duration_seconds` — latência (histogram P50/P95)
- `cache_hits_total` / `cache_misses_total` — eficiência do cache
- `users_registered_total` — contador de registros
- `http_requests_in_progress` — requests ativas

### Grafana
```bash
kubectl port-forward svc/grafana 3000:3000 -n fcg-tech-fase-2
# Acesse: http://localhost:3000 (admin/admin)
```

Importe o dashboard: `k8s/grafana-dashboard.json` — 12 painéis incluindo:
- APIs Status (UP/DOWN)
- Request Rate por API e Endpoint
- Latência P95/P50
- Cache Hit Rate (gauge)
- Cache Hits vs Misses
- Taxa de Erros (4xx + 5xx)

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
| Kong Proxy | http://localhost:9080 | API Gateway (ponto de entrada) |
| Users API | http://localhost:8080 | Registro e login |
| Payments API | http://localhost:8081 | Processamento de pagamentos |
| Catalog API | http://localhost:8083 | Catálogo de jogos (CRUD) |
| Notification API | http://localhost:8083 | Envio de notificações |
| RabbitMQ UI | http://localhost:15672 | Management (admin / admin123) |
| Prometheus | http://localhost:9090 | Métricas e targets |
| Grafana | http://localhost:3000 | Dashboards (admin / admin) |
| Redis | localhost:6379 | Cache (password: redis@123) |
| Kong Admin | http://localhost:8001 | Admin API do Kong |

Se os port-forwards caírem, reinicie manualmente:

```bash
kubectl port-forward svc/users-api 8080:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/payments-api 8081:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/catalog-api 8083:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/notification-api 8084:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/kong-proxy 9080:80 -n fcg-tech-fase-2 &
kubectl port-forward svc/prometheus 9090:9090 -n fcg-tech-fase-2 &
kubectl port-forward svc/grafana 3000:3000 -n fcg-tech-fase-2 &
kubectl port-forward svc/redis 6379:6379 -n fcg-tech-fase-2 &
kubectl port-forward svc/rabbitmq 15672:15672 -n fcg-tech-fase-2 &
```

---

## 🏛️ Arquitetura

```
                          ┌──────────────┐
          Internet ──────►│ Kong Gateway │ (JWT + CORS + Routing)
                          └──────┬───────┘
                                 │
            ┌────────────────────┼────────────────────┐
            │                    │                    │
     ┌──────▼──────┐     ┌──────▼──────┐     ┌──────▼───────┐
     │  Users API  │     │ Catalog API │     │ Payments API │
     │  (v2)       │     │  (v2)       │     │   (v1)       │
     └──────┬──────┘     └──────┬──────┘     └──────┬───────┘
            │                   │                   │
            ├───── Redis Cache ─┤                   │
            │                   │                   │
            │ UserCreated       │                   │ PaymentProcessed
            │                   │                   │
            └───────────────────┴───────────────────┘
                                │
                         ┌──────▼──────┐
                         │  RabbitMQ   │
                         └──────┬──────┘
                                │
                         ┌──────▼──────────┐
                         │  ORCHESTRATOR   │ ─── MongoDB (Logs)
                         │  (v5)           │
                         └──────┬──────────┘
                                │
                         Publica eventos:
                    NotificationEvent
                    PaymentRequestEvent
                    CatalogUpdateEvent
```

```
         ┌──────────────┐        ┌─────────────┐
         │  Prometheus  │◄───────│ UsersAPI     │ /metrics
         │  (scrape)    │◄───────│ CatalogAPI   │ /metrics
         │              │◄───────│ PaymentsAPI  │ /metrics
         └──────┬───────┘        └─────────────┘
                │
         ┌──────▼──────┐
         │   Grafana   │ ← 12 painéis (dashboard JSON)
         └─────────────┘
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
│   ├── test-load-users.sh                  # 📊 Teste de carga (210 requests)
│   ├── kong-setup.sh                       # 🔐 Configuração do Kong via Admin API
│   ├── grafana-dashboard.json              # 📈 Dashboard Grafana (12 painéis)
│   ├── postman-kong-collection.json        # 📮 Collection Postman (20 requests)
│   ├── 00-namespace.yaml
│   ├── kong-deployment.yaml                # Kong Gateway + Admin
│   ├── kong-configmap.yaml                 # Configuração declarativa do Kong
│   ├── redis-deployment.yaml               # Redis 7 (cache)
│   ├── redis-secret.yaml
│   ├── prometheus-deployment.yaml          # Prometheus (métricas)
│   ├── grafana-deployment.yaml             # Grafana 10.4.2 (dashboards)
│   ├── postgres-deployment.yaml            # PostgreSQL (3 databases)
│   ├── mongodb-deployment.yaml
│   ├── sqlserver-deployment.yaml           # SQL Server (Notification API)
│   ├── rabbitmq-deployment.yaml
│   ├── orchestrator-deployment.yaml
│   ├── users-api-deployment.yaml           # UsersAPI v2 + Redis env vars
│   ├── catalog-api-deployment.yaml         # CatalogAPI v2 + Redis env vars
│   ├── payments-api-deployment.yaml
│   ├── notification-api-deployment.yaml
│   ├── init-catalog-tables.sql             # DDL do Catalog (Games, Outbox)
│   └── init-catalog-extra-tables.sql       # DDL do Catalog (Orders, Library)
├── docs/
│   ├── postman-kong-collection.json        # 📮 Collection Postman (cópia)
│   ├── INTEGRACAO_CACHE_KONG_PROMETHEUS.md  # Guia de integração completo
│   └── ...
├── tests/                                  # Testes unitários e integração
├── Dockerfile
├── docker-compose.yml
└── Orchestrator.sln
```

---

## 🗄️ Bancos de Dados e Serviços

| Serviço | Tecnologia | Uso | Detalhes |
|---------|-----------|-----|----------|
| PostgreSQL | postgres:15-alpine | Users, Payments, Catalog | 3 databases: `fcg_users_db`, `fcg_payments_db`, `fcg_catalog_db` |
| SQL Server | Azure SQL Edge | Notification API | `fcg_notifications_db` |
| MongoDB | mongo:4.4 | Orchestrator Logs | Database: `orchestrator`, Collection: `Logs` |
| Redis | redis:7-alpine | Cache distribuído | Password: `redis@123`, prefixos: `users:`, `catalog:` |
| RabbitMQ | rabbitmq:3-management | Message Broker | admin/admin123, 10 filas |
| Kong | kong:3.4 | API Gateway | JWT HS256, CORS global |
| Prometheus | prom/prometheus | Métricas | Scrape 5 APIs + self |
| Grafana | grafana:10.4.2 | Dashboards | PVC persistente (1Gi) |

---

## 🔍 Comandos úteis

```bash
# Status dos pods
kubectl get pods -n fcg-tech-fase-2

# Logs do Orchestrator
kubectl logs deployment/orchestrator -n fcg-tech-fase-2 --tail=30

# Eventos no MongoDB
kubectl exec deployment/mongodb -n fcg-tech-fase-2 -- mongo orchestrator \
  --quiet --authenticationDatabase admin -u admin -p mongo@123 \
  --eval 'db.Logs.find().sort({CreatedAt:-1}).limit(5).forEach(function(d){printjson(d)})'

# Buscar evento por UserId (Payload é string JSON, usar regex)
kubectl exec deployment/mongodb -n fcg-tech-fase-2 -- mongo orchestrator \
  --quiet --authenticationDatabase admin -u admin -p mongo@123 \
  --eval 'db.Logs.find({ Payload: /SEU-USER-ID-AQUI/ }).pretty()'

# Filas do RabbitMQ
kubectl exec deployment/rabbitmq -n fcg-tech-fase-2 -- \
  rabbitmqctl list_queues name messages consumers

# Chaves no Redis
kubectl exec deployment/redis -n fcg-tech-fase-2 -- \
  redis-cli -a 'redis@123' --no-auth-warning KEYS '*'

# Métricas do Prometheus (via API)
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool

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
| API Gateway | Kong 3.4 (JWT HS256 + CORS) |
| Cache | Redis 7 + FCGLibCache v1.0.1 |
| Message Broker | RabbitMQ 3.x (com MassTransit) |
| Log Database | MongoDB 4.4 |
| API Databases | PostgreSQL 15 + SQL Server (Azure SQL Edge) |
| Métricas | Prometheus + prometheus-net.AspNetCore v8.2.1 |
| Dashboards | Grafana 10.4.2 |
| Containers | Docker |
| Orquestração | Kubernetes (Docker Desktop) |
| Testes | xUnit + Moq + Mongo2Go |

---

## 🐳 Imagens Docker

| Serviço | Imagem | Versão |
|---------|--------|--------|
| Orchestrator | `davidjmarinho/orchestrator` | v5 |
| Users API | `davidjmarinho/users-api` | v2 |
| Catalog API | `davidjmarinho/catalog-api` | v2 |
| Payments API | `davidjmarinho/payments-api` | v1 |
| Notification API | `davidjmarinho/notification-api` | v1 |
