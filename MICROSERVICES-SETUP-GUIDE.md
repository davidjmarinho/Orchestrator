# 📘 Guia de Configuração dos Microserviços

Este documento descreve **como cada microserviço/API deve ser estruturado** para funcionar com o Orchestrator, incluindo Dockerfile, docker-compose.yml e manifestos Kubernetes.

---

## 📋 Índice

- [Estrutura de Diretórios](#-estrutura-de-diretórios)
- [Dockerfile](#-dockerfile)
- [docker-compose.yml](#-docker-composeyml)
- [Pasta k8s/](#-pasta-k8s)
- [Exemplos por Microserviço](#-exemplos-por-microserviço)
  - [Users API](#1-users-api)
  - [Orders API](#2-orders-api)
  - [Payments API](#3-payments-api)
  - [Notification API](#4-notification-api)
  - [Catalog API](#5-catalog-api)
- [Checklist de Implementação](#-checklist-de-implementação)

---

## 📁 Estrutura de Diretórios

Cada microserviço deve seguir esta estrutura:

```
users-api/                          # Nome do microserviço
├── src/
│   ├── UsersAPI/
│   │   ├── Controllers/
│   │   │   └── UsersController.cs
│   │   ├── Models/
│   │   ├── Services/
│   │   ├── Infrastructure/
│   │   │   ├── MessageBus/
│   │   │   │   └── RabbitMqPublisher.cs
│   │   │   └── Database/
│   │   ├── Program.cs
│   │   └── UsersAPI.csproj
│   └── UsersAPI.Tests/
├── k8s/                            # ⭐ Manifestos Kubernetes
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── secret.yaml
├── Dockerfile                      # ⭐ Build da imagem
├── docker-compose.yml              # ⭐ Desenvolvimento local
├── .dockerignore
├── .env.example
└── README.md
```

---

## 🐳 Dockerfile

Cada API deve ter um **Dockerfile multi-stage** otimizado para .NET:

### 📄 Modelo de Dockerfile

```dockerfile
# ============================================
# Stage 1: Build
# ============================================
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

# Copiar arquivos de projeto e restaurar dependências
COPY ["src/UsersAPI/UsersAPI.csproj", "UsersAPI/"]
RUN dotnet restore "UsersAPI/UsersAPI.csproj"

# Copiar código fonte
COPY src/UsersAPI/ UsersAPI/

# Build da aplicação
WORKDIR "/src/UsersAPI"
RUN dotnet build "UsersAPI.csproj" -c Release -o /app/build

# ============================================
# Stage 2: Publish
# ============================================
FROM build AS publish
RUN dotnet publish "UsersAPI.csproj" -c Release -o /app/publish /p:UseAppHost=false

# ============================================
# Stage 3: Runtime
# ============================================
FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app

# Criar usuário não-root
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Copiar binários publicados
COPY --from=publish /app/publish .

# Expor porta
EXPOSE 80
EXPOSE 443

# Trocar para usuário não-root
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD curl -f http://localhost/health || exit 1

# Entry point
ENTRYPOINT ["dotnet", "UsersAPI.dll"]
```

### 📄 .dockerignore

```
**/.dockerignore
**/.env
**/.git
**/.gitignore
**/.vs
**/.vscode
**/*.*proj.user
**/*.dbmdl
**/*.jfm
**/bin
**/charts
**/docker-compose*
**/compose*
**/Dockerfile*
**/node_modules
**/npm-debug.log
**/obj
**/secrets.dev.yaml
**/values.dev.yaml
LICENSE
README.md
```

---

## 🐋 docker-compose.yml

Cada microserviço deve ter seu próprio `docker-compose.yml` para **desenvolvimento local**.

### 📄 Modelo de docker-compose.yml

```yaml
version: '3.8'

services:
  # ========================================
  # API Principal
  # ========================================
  users-api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: users-api
    ports:
      - "5001:80"
    environment:
      # ASP.NET Core
      - ASPNETCORE_ENVIRONMENT=Development
      - ASPNETCORE_URLS=http://+:80
      
      # Database (PostgreSQL)
      - DATABASE_HOST=postgres
      - DATABASE_PORT=5432
      - DATABASE_NAME=usersdb
      - DATABASE_USER=${DB_USER:-postgres}
      - DATABASE_PASSWORD=${DB_PASSWORD:-postgres123}
      
      # RabbitMQ
      - RABBITMQ_HOST=rabbitmq
      - RABBITMQ_PORT=5672
      - RABBITMQ_USER=${RABBITMQ_USER:-admin}
      - RABBITMQ_PASS=${RABBITMQ_PASS:-admin123}
      
      # Logging
      - Logging__LogLevel__Default=Information
      - Logging__LogLevel__Microsoft.AspNetCore=Warning
    
    depends_on:
      postgres:
        condition: service_healthy
      rabbitmq:
        condition: service_healthy
    
    networks:
      - users-network
    
    restart: unless-stopped
    
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

  # ========================================
  # PostgreSQL (Banco de Dados)
  # ========================================
  postgres:
    image: postgres:15-alpine
    container_name: users-postgres
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_USER=${DB_USER:-postgres}
      - POSTGRES_PASSWORD=${DB_PASSWORD:-postgres123}
      - POSTGRES_DB=usersdb
      - PGDATA=/var/lib/postgresql/data/pgdata
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./scripts/init-db.sql:/docker-entrypoint-initdb.d/init-db.sql
    networks:
      - users-network
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  # ========================================
  # RabbitMQ (Message Broker)
  # ========================================
  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: users-rabbitmq
    ports:
      - "5672:5672"   # AMQP
      - "15672:15672" # Management UI
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:-admin}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS:-admin123}
    volumes:
      - rabbitmq-data:/var/lib/rabbitmq
    networks:
      - users-network
    restart: unless-stopped
    healthcheck:
      test: rabbitmq-diagnostics -q ping
      interval: 10s
      timeout: 5s
      retries: 5

networks:
  users-network:
    driver: bridge

volumes:
  postgres-data:
  rabbitmq-data:
```

### 📄 .env.example

```bash
# Database
DB_USER=postgres
DB_PASSWORD=postgres123

# RabbitMQ
RABBITMQ_USER=admin
RABBITMQ_PASS=admin123

# Application
ASPNETCORE_ENVIRONMENT=Development
```

---

## ☸️ Pasta k8s/

Cada microserviço deve ter uma pasta `k8s/` com os seguintes manifestos:

### 📁 Estrutura k8s/

```
k8s/
├── deployment.yaml      # Deployment do microserviço
├── service.yaml        # Service para expor o pod
├── configmap.yaml      # Configurações não sensíveis
└── secret.yaml         # Credenciais e dados sensíveis
```

---

### 📄 1. deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: users-api
  namespace: fcg-tech-fase-2
  labels:
    app: users-api
    version: v1
    component: api
spec:
  replicas: 2                    # Número de réplicas
  
  selector:
    matchLabels:
      app: users-api
  
  strategy:
    type: RollingUpdate          # Estratégia de atualização
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  
  template:
    metadata:
      labels:
        app: users-api
        version: v1
    
    spec:
      # Security Context
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      
      containers:
      - name: users-api
        image: davidjmarinho/users-api:v1    # ⭐ Sua imagem Docker
        imagePullPolicy: Always
        
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        
        # ========================================
        # Variáveis de Ambiente
        # ========================================
        env:
        # ASP.NET Core
        - name: ASPNETCORE_ENVIRONMENT
          value: Production
        - name: ASPNETCORE_URLS
          value: http://+:80
        
        # Database
        - name: DATABASE_HOST
          value: postgres
        - name: DATABASE_PORT
          value: "5432"
        - name: DATABASE_NAME
          valueFrom:
            configMapKeyRef:
              name: users-config
              key: database-name
        - name: DATABASE_USER
          valueFrom:
            secretKeyRef:
              name: users-secret
              key: db-username
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: users-secret
              key: db-password
        
        # RabbitMQ
        - name: RABBITMQ_HOST
          value: rabbitmq
        - name: RABBITMQ_PORT
          value: "5672"
        - name: RABBITMQ_USER
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: username
        - name: RABBITMQ_PASS
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: password
        
        # ========================================
        # Resources
        # ========================================
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        
        # ========================================
        # Health Checks
        # ========================================
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
        
        # ========================================
        # Startup Probe (para inicialização lenta)
        # ========================================
        startupProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 30
      
      # ========================================
      # Restart Policy
      # ========================================
      restartPolicy: Always
```

---

### 📄 2. service.yaml

```yaml
apiVersion: v1
kind: Service
metadata:
  name: users-api
  namespace: fcg-tech-fase-2
  labels:
    app: users-api
spec:
  type: ClusterIP              # ClusterIP para serviços internos
  
  selector:
    app: users-api
  
  ports:
  - port: 80                   # Porta do service
    targetPort: 80             # Porta do container
    protocol: TCP
    name: http
  
  sessionAffinity: None
```

**Para serviços que precisam ser acessados externamente:**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: users-api-external
  namespace: fcg-tech-fase-2
spec:
  type: LoadBalancer          # Ou NodePort para Docker Desktop
  selector:
    app: users-api
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30001           # Apenas para NodePort
    protocol: TCP
```

---

### 📄 3. configmap.yaml

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: users-config
  namespace: fcg-tech-fase-2
data:
  # Database
  database-name: "usersdb"
  database-port: "5432"
  
  # RabbitMQ Queues
  queue-user-created: "user.created"
  exchange-name: "users-exchange"
  
  # Application Settings
  app-name: "Users API"
  app-version: "v1.0.0"
  
  # Logging
  log-level: "Information"
  
  # CORS (se necessário)
  cors-origins: "http://localhost:3000,http://localhost:5173"
```

---

### 📄 4. secret.yaml

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: users-secret
  namespace: fcg-tech-fase-2
type: Opaque
data:
  # Database Credentials (base64 encoded)
  db-username: cG9zdGdyZXM=           # postgres
  db-password: cG9zdGdyZXMMTIz        # postgres123
  
  # JWT Secret (se aplicável)
  jwt-secret: bXktc3VwZXItc2VjcmV0LWtleS1mb3Itand0  # my-super-secret-key-for-jwt
  
  # API Keys (se aplicável)
  api-key: YXBpLWtleS0xMjM0NTY3ODkw              # api-key-1234567890
```

**Como gerar base64:**

```bash
echo -n "postgres" | base64        # cG9zdGdyZXM=
echo -n "postgres123" | base64     # cG9zdGdyZXMxMjM=
```

---

## 🎯 Exemplos por Microserviço

### 1. Users API

#### 📁 Estrutura Completa

```
users-api/
├── src/
│   └── UsersAPI/
│       ├── Controllers/
│       │   └── UsersController.cs
│       ├── Models/
│       │   ├── User.cs
│       │   └── CreateUserRequest.cs
│       ├── Services/
│       │   └── UserService.cs
│       ├── Infrastructure/
│       │   ├── MessageBus/
│       │   │   ├── IMessageBus.cs
│       │   │   └── RabbitMqPublisher.cs
│       │   └── Database/
│       │       ├── UsersDbContext.cs
│       │       └── UserRepository.cs
│       ├── Events/
│       │   └── UserCreatedEvent.cs
│       ├── Program.cs
│       └── UsersAPI.csproj
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── configmap.yaml
│   └── secret.yaml
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── .env.example
└── README.md
```

#### 📄 UserCreatedEvent.cs

```csharp
namespace UsersAPI.Events
{
    public class UserCreatedEvent
    {
        public string UserId { get; set; }
        public string Email { get; set; }
        public string Name { get; set; }
        public DateTime CreatedAt { get; set; }
    }
}
```

#### 📄 UsersController.cs

```csharp
using Microsoft.AspNetCore.Mvc;
using UsersAPI.Models;
using UsersAPI.Services;
using UsersAPI.Events;
using UsersAPI.Infrastructure.MessageBus;

namespace UsersAPI.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class UsersController : ControllerBase
    {
        private readonly IUserService _userService;
        private readonly IMessageBus _messageBus;
        private readonly ILogger<UsersController> _logger;

        public UsersController(
            IUserService userService, 
            IMessageBus messageBus,
            ILogger<UsersController> logger)
        {
            _userService = userService;
            _messageBus = messageBus;
            _logger = logger;
        }

        [HttpPost]
        public async Task<IActionResult> CreateUser([FromBody] CreateUserRequest request)
        {
            try
            {
                // 1. Criar usuário no banco de dados
                var user = await _userService.CreateAsync(request);
                
                _logger.LogInformation("User created: {UserId}", user.Id);

                // 2. Publicar evento para o Orchestrator
                var userCreatedEvent = new UserCreatedEvent
                {
                    UserId = user.Id,
                    Email = user.Email,
                    Name = user.Name,
                    CreatedAt = DateTime.UtcNow
                };

                await _messageBus.PublishAsync("user.created", userCreatedEvent);
                
                _logger.LogInformation("UserCreatedEvent published for user: {UserId}", user.Id);

                // 3. Retornar resposta
                return CreatedAtAction(nameof(GetUser), new { id = user.Id }, user);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error creating user");
                return StatusCode(500, "Internal server error");
            }
        }

        [HttpGet("{id}")]
        public async Task<IActionResult> GetUser(string id)
        {
            var user = await _userService.GetByIdAsync(id);
            
            if (user == null)
                return NotFound();
            
            return Ok(user);
        }

        [HttpGet("health")]
        public IActionResult Health()
        {
            return Ok(new { status = "healthy", timestamp = DateTime.UtcNow });
        }

        [HttpGet("health/ready")]
        public async Task<IActionResult> Ready()
        {
            // Verificar dependências (DB, RabbitMQ)
            var dbHealthy = await _userService.CheckDatabaseHealthAsync();
            var rabbitHealthy = _messageBus.IsConnected();

            if (!dbHealthy || !rabbitHealthy)
                return StatusCode(503, "Service not ready");

            return Ok(new { status = "ready" });
        }
    }
}
```

#### 📄 k8s/configmap.yaml (Users API)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: users-config
  namespace: fcg-tech-fase-2
data:
  database-name: "usersdb"
  queue-name: "user.created"
  app-name: "Users API"
```

---

### 2. Orders API

#### 📄 Dockerfile (Orders API)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY ["src/OrdersAPI/OrdersAPI.csproj", "OrdersAPI/"]
RUN dotnet restore "OrdersAPI/OrdersAPI.csproj"
COPY src/OrdersAPI/ OrdersAPI/
WORKDIR "/src/OrdersAPI"
RUN dotnet build "OrdersAPI.csproj" -c Release -o /app/build
RUN dotnet publish "OrdersAPI.csproj" -c Release -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
COPY --from=build /app/publish .
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost/health || exit 1
ENTRYPOINT ["dotnet", "OrdersAPI.dll"]
```

#### 📄 docker-compose.yml (Orders API)

```yaml
version: '3.8'

services:
  orders-api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: orders-api
    ports:
      - "5002:80"
    environment:
      - ASPNETCORE_ENVIRONMENT=Development
      - DATABASE_HOST=postgres
      - DATABASE_NAME=ordersdb
      - DATABASE_USER=${DB_USER:-postgres}
      - DATABASE_PASSWORD=${DB_PASSWORD:-postgres123}
      - RABBITMQ_HOST=rabbitmq
      - RABBITMQ_USER=${RABBITMQ_USER:-admin}
      - RABBITMQ_PASS=${RABBITMQ_PASS:-admin123}
    depends_on:
      - postgres
      - rabbitmq
    networks:
      - orders-network

  postgres:
    image: postgres:15-alpine
    container_name: orders-postgres
    ports:
      - "5433:5432"
    environment:
      - POSTGRES_DB=ordersdb
      - POSTGRES_USER=${DB_USER:-postgres}
      - POSTGRES_PASSWORD=${DB_PASSWORD:-postgres123}
    volumes:
      - postgres-data:/var/lib/postgresql/data
    networks:
      - orders-network

  rabbitmq:
    image: rabbitmq:3-management-alpine
    container_name: orders-rabbitmq
    ports:
      - "5673:5672"
      - "15673:15672"
    environment:
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER:-admin}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS:-admin123}
    networks:
      - orders-network

networks:
  orders-network:

volumes:
  postgres-data:
```

#### 📄 k8s/configmap.yaml (Orders API)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: orders-config
  namespace: fcg-tech-fase-2
data:
  database-name: "ordersdb"
  queue-order-placed: "order.placed"
  queue-payment-request: "payment.request"
  app-name: "Orders API"
```

---

### 3. Payments API

#### 📄 k8s/deployment.yaml (Payments API - Específico)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-api
  namespace: fcg-tech-fase-2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payments-api
  template:
    metadata:
      labels:
        app: payments-api
    spec:
      containers:
      - name: payments-api
        image: davidjmarinho/payments-api:v1
        ports:
        - containerPort: 80
        env:
        - name: ASPNETCORE_ENVIRONMENT
          value: Production
        - name: DATABASE_NAME
          value: paymentsdb
        - name: DATABASE_HOST
          value: postgres
        - name: DATABASE_USER
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: username
        - name: DATABASE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: postgres-secret
              key: password
        - name: RABBITMQ_HOST
          value: rabbitmq
        - name: RABBITMQ_USER
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: username
        - name: RABBITMQ_PASS
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: password
        # Configurações específicas de pagamento
        - name: PAYMENT_GATEWAY_URL
          valueFrom:
            configMapKeyRef:
              name: payments-config
              key: gateway-url
        - name: PAYMENT_GATEWAY_API_KEY
          valueFrom:
            secretKeyRef:
              name: payments-secret
              key: gateway-api-key
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 5
```

#### 📄 k8s/configmap.yaml (Payments API)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: payments-config
  namespace: fcg-tech-fase-2
data:
  database-name: "paymentsdb"
  queue-payment-request: "payment.request"
  queue-payment-processed: "payment.processed"
  gateway-url: "https://payment-gateway.example.com"
  retry-attempts: "3"
  timeout-seconds: "30"
```

---

### 4. Notification API

#### 📄 k8s/deployment.yaml (Notification API - Consumer)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: notification-api
  namespace: fcg-tech-fase-2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: notification-api
  template:
    metadata:
      labels:
        app: notification-api
    spec:
      containers:
      - name: notification-api
        image: davidjmarinho/notification-api:v1
        ports:
        - containerPort: 80
        env:
        - name: ASPNETCORE_ENVIRONMENT
          value: Production
        - name: RABBITMQ_HOST
          value: rabbitmq
        - name: RABBITMQ_USER
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: username
        - name: RABBITMQ_PASS
          valueFrom:
            secretKeyRef:
              name: rabbitmq-secret
              key: password
        # Configurações de Email
        - name: SMTP_HOST
          valueFrom:
            configMapKeyRef:
              name: notification-config
              key: smtp-host
        - name: SMTP_PORT
          valueFrom:
            configMapKeyRef:
              name: notification-config
              key: smtp-port
        - name: SMTP_USER
          valueFrom:
            secretKeyRef:
              name: notification-secret
              key: smtp-user
        - name: SMTP_PASSWORD
          valueFrom:
            secretKeyRef:
              name: notification-secret
              key: smtp-password
        - name: EMAIL_FROM
          valueFrom:
            configMapKeyRef:
              name: notification-config
              key: email-from
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
```

#### 📄 k8s/configmap.yaml (Notification API)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: notification-config
  namespace: fcg-tech-fase-2
data:
  queue-notification: "notification.send"
  smtp-host: "smtp.gmail.com"
  smtp-port: "587"
  email-from: "noreply@example.com"
  enable-ssl: "true"
```

---

### 5. Catalog API

#### 📄 k8s/configmap.yaml (Catalog API)

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: catalog-config
  namespace: fcg-tech-fase-2
data:
  database-name: "catalogdb"
  queue-catalog-update: "catalog.update"
  cache-ttl-minutes: "30"
  enable-cache: "true"
```

---

## ✅ Checklist de Implementação

Use esta checklist para cada microserviço:

### 📋 Estrutura Básica
- [ ] Criar diretório do projeto
- [ ] Estruturar src/ com Controllers, Models, Services
- [ ] Criar pasta k8s/
- [ ] Criar Dockerfile
- [ ] Criar docker-compose.yml
- [ ] Criar .dockerignore
- [ ] Criar .env.example
- [ ] Criar README.md

### 🐳 Docker
- [ ] Dockerfile com multi-stage build
- [ ] Health check configurado no Dockerfile
- [ ] Imagem otimizada (< 200MB se possível)
- [ ] docker-compose.yml com todos os serviços necessários
- [ ] Variáveis de ambiente definidas
- [ ] Volumes configurados para persistência

### ☸️ Kubernetes
- [ ] deployment.yaml criado
- [ ] service.yaml criado
- [ ] configmap.yaml criado
- [ ] secret.yaml criado
- [ ] Namespace correto (fcg-tech-fase-2)
- [ ] Labels consistentes
- [ ] Health checks (liveness, readiness, startup)
- [ ] Resources (requests e limits) definidos
- [ ] Variáveis de ambiente do RabbitMQ
- [ ] Variáveis de ambiente do Database

### 📨 Integração com Orchestrator
- [ ] RabbitMQ Client instalado (RabbitMQ.Client NuGet)
- [ ] Interface IMessageBus implementada
- [ ] Eventos publicados nas rotas corretas
- [ ] Eventos serializados como JSON
- [ ] Logging de eventos publicados
- [ ] Tratamento de erros na publicação

### 🔐 Segurança
- [ ] Secrets não commitados no Git
- [ ] .env no .gitignore
- [ ] Secrets em base64 no Kubernetes
- [ ] Container rodando como non-root
- [ ] Passwords fortes configurados

### 🔍 Observabilidade
- [ ] Endpoint /health implementado
- [ ] Endpoint /health/ready implementado
- [ ] Logs estruturados (JSON)
- [ ] Correlation IDs nos logs
- [ ] Métricas básicas (se aplicável)

### 🧪 Testes
- [ ] Build do Docker funciona
- [ ] docker-compose up funciona
- [ ] Health checks respondem corretamente
- [ ] Conectividade com RabbitMQ
- [ ] Conectividade com Database
- [ ] Eventos são publicados corretamente

---

## 🚀 Comandos Úteis

### Build e Push da Imagem

```bash
# Build
docker build -t davidjmarinho/users-api:v1 .

# Test local
docker run -p 8080:80 davidjmarinho/users-api:v1

# Push para Docker Hub
docker push davidjmarinho/users-api:v1
```

### Testar com docker-compose

```bash
# Subir
docker-compose up -d

# Ver logs
docker-compose logs -f users-api

# Testar API
curl http://localhost:5001/health

# Parar
docker-compose down
```

### Deploy no Kubernetes

```bash
# Aplicar todos os manifestos
kubectl apply -f k8s/

# Verificar pod
kubectl get pods -n fcg-tech-fase-2 -l app=users-api

# Ver logs
kubectl logs -f deployment/users-api -n fcg-tech-fase-2

# Port-forward para testar
kubectl port-forward svc/users-api 8080:80 -n fcg-tech-fase-2

# Testar
curl http://localhost:8080/health
```

---

## 📚 Recursos Adicionais

### Documentação Oficial
- [.NET Microservices](https://docs.microsoft.com/en-us/dotnet/architecture/microservices/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [RabbitMQ .NET Client](https://www.rabbitmq.com/dotnet-api-guide.html)

### Templates de Projeto
```bash
# Criar projeto .NET
dotnet new webapi -n UsersAPI

# Adicionar RabbitMQ Client
dotnet add package RabbitMQ.Client

# Adicionar Entity Framework
dotnet add package Npgsql.EntityFrameworkCore.PostgreSQL
```

---

## 🎯 Resultado Final

Ao seguir este guia, cada microserviço terá:

✅ **Dockerfile otimizado** para build rápido  
✅ **docker-compose.yml** para desenvolvimento local  
✅ **Manifestos Kubernetes completos** (deployment, service, configmap, secret)  
✅ **Integração com RabbitMQ** para comunicação assíncrona  
✅ **Health checks** para monitoramento  
✅ **Configurações seguras** com secrets separados  
✅ **Pronto para deploy** no cluster Kubernetes  

E tudo funcionando perfeitamente com o **Orchestrator**! 🎉

---

**Desenvolvido com ❤️ para o ecossistema de microserviços FCG Tech Fase 2**
