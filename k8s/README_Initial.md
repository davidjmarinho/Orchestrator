# Guia de Inicialização do Ambiente — Do Zero

Este guia descreve todos os passos para um desenvolvedor subir o ambiente completo do projeto em uma máquina nova.

---

## Visão Geral do Ecossistema

```
┌─────────────────────────────────────────────────────────────────┐
│                    Kubernetes (Docker Desktop)                   │
│  Namespace: fcg-tech-fase-2                                      │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐    │
│  │ users-api│  │catalog-api│ │payments  │  │notification  │    │
│  │ (Worker) │  │ (Worker) │  │-api      │  │-api (Worker) │    │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘    │
│       └──────────────┴────────────┴────────────────┘            │
│                             │                                    │
│                      ┌──────▼──────┐                            │
│                      │  RabbitMQ   │                            │
│                      └──────┬──────┘                            │
│                             │                                    │
│                      ┌──────▼──────┐                            │
│                      │Orchestrator │                            │
│                      └──────┬──────┘                            │
│                             │                                    │
│                      ┌──────▼──────┐                            │
│                      │   MongoDB   │  ← logs de eventos         │
│                      └─────────────┘                            │
│                                                                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                       │
│  │PostgreSQL│  │SQL Server│  │Kong DB   │                       │
│  │(Catalog) │  │(Payments)│  │(Postgres)│                       │
│  └──────────┘  └──────────┘  └──────────┘                       │
│                                                                  │
│  ┌──────────────────────────────────┐                           │
│  │  Kong (API Gateway)  :9080       │                           │
│  │  Konga (GUI)         :1337       │                           │
│  │  mock-api (nginx)    interno     │                           │
│  └──────────────────────────────────┘                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## Pré-requisitos

### Software obrigatório

| Software | Versão mínima | Download |
|---|---|---|
| Docker Desktop | 4.x | https://www.docker.com/products/docker-desktop |
| kubectl | 1.28+ | Incluído no Docker Desktop |
| Git | qualquer | https://git-scm.com |
| Bash | qualquer | WSL2 (Windows) / nativo (Linux/macOS) |
| Python 3 | 3.8+ | https://www.python.org (usado nos scripts de output) |
| curl | qualquer | Incluído no Linux/macOS / Git Bash no Windows |

### Configurar Docker Desktop (Windows)

1. Abrir Docker Desktop → **Settings** → **Kubernetes**
2. Marcar **Enable Kubernetes**
3. Clicar **Apply & Restart**
4. Aguardar o ícone do Kubernetes ficar verde

### Verificar pré-requisitos

```bash
docker --version       # Docker version 24.x ou superior
kubectl version        # Client e Server devem aparecer
kubectl config current-context   # deve retornar: docker-desktop
python3 --version      # Python 3.x.x (ou python --version no Windows)
curl --version         # curl x.x.x
```

> **Windows**: execute os comandos acima no **WSL2** ou **Git Bash**. O PowerShell pode ser usado para os testes, mas os scripts `.sh` precisam de Bash.

---

## Passo 1 — Clonar o Repositório

```bash
git clone <url-do-repositorio>
cd Orchestrator
```

---

## Passo 2 — Deploy Base do Ecossistema

Este passo sobe **toda a infraestrutura** (bancos, RabbitMQ, Orchestrator e microserviços) com um único comando.

```bash
bash k8s/deploy.sh --destroy
```

> `--destroy` remove qualquer ambiente anterior e recria do zero. Na primeira vez, use sem `--destroy` ou com ele (efeito igual).

O script realiza automaticamente:

| Etapa | O que faz |
|---|---|
| 1 | Cria namespace `fcg-tech-fase-2` |
| 2 | Aplica Secrets (MongoDB, Orchestrator) |
| 3 | Aplica ConfigMaps |
| 4 | Sobe MongoDB, PostgreSQL e SQL Server |
| 5 | Sobe RabbitMQ |
| 6 | Sobe Orchestrator |
| 7 | Sobe 4 microserviços Workers (Users, Payments, Catalog, Notification) |
| 8 | Cria tabelas do Catalog API no PostgreSQL |
| 9 | Configura bindings do RabbitMQ |

**Duração**: ~2-5 minutos

### Verificar se o deploy base funcionou

```bash
kubectl get pods -n fcg-tech-fase-2
```

Todos os pods devem estar `Running`:

```
catalog-api-xxxxx       1/1   Running
mongodb-xxxxx           1/1   Running
notification-api-xxxxx  1/1   Running
orchestrator-xxxxx      1/1   Running
payments-api-xxxxx      1/1   Running
postgres-xxxxx          1/1   Running
rabbitmq-xxxxx          1/1   Running
sqlserver-xxxxx         1/1   Running
users-api-xxxxx         1/1   Running
```

---

## Passo 3 — Deploy do Kong (API Gateway)

### 3.1 Aplicar YAMLs do Kong

```bash
kubectl apply -f k8s/kong-secret.yaml             -n fcg-tech-fase-2
kubectl apply -f k8s/kong-database-deployment.yaml -n fcg-tech-fase-2
```

Aguardar o banco do Kong:

```bash
kubectl wait --for=condition=ready pod -l app=kong-database \
  -n fcg-tech-fase-2 --timeout=120s
```

```bash
kubectl apply -f k8s/kong-deployment.yaml   -n fcg-tech-fase-2
kubectl apply -f k8s/konga-deployment.yaml  -n fcg-tech-fase-2
kubectl apply -f k8s/mock-api-deployment.yaml -n fcg-tech-fase-2
```

Aguardar Kong e Konga:

```bash
kubectl wait --for=condition=ready pod -l app=kong  -n fcg-tech-fase-2 --timeout=120s
kubectl wait --for=condition=ready pod -l app=konga -n fcg-tech-fase-2 --timeout=120s
```

Verificar:

```bash
kubectl get pods -n fcg-tech-fase-2
```

Novos pods esperados:

```
kong-xxxxx              1/1   Running
kong-database-xxxxx     1/1   Running
konga-xxxxx             1/1   Running
mock-api-xxxxx          1/1   Running
```

### 3.2 Abrir Port-Forwards (terminais dedicados)

Abra **3 terminais separados** e execute um comando em cada:

```bash
# Terminal A — Kong Admin API (configuração)
kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2

# Terminal B — Kong Proxy (requisições de negócio)
kubectl port-forward svc/kong-proxy 9080:80 -n fcg-tech-fase-2

# Terminal C — Konga GUI (opcional)
kubectl port-forward svc/konga 1337:1337 -n fcg-tech-fase-2
```

> Mantenha esses terminais abertos durante todo o uso.

### 3.3 Configurar Rotas e Políticas Kong

Com o Terminal A ativo, execute em um **novo terminal**:

```bash
bash k8s/kong-setup.sh
```

Saída esperada:
```
✅ CORS configurado
✅ Serviço users-api criado
✅ Rota pública criada
✅ Rota protegida users criada
✅ Serviço catalog-api criado
✅ Consumer criado
✅ Credencial JWT configurada
✅ KONG CONFIGURADO COM SUCESSO!
```

### 3.4 Apontar Kong para o Mock Backend

Os microserviços Workers não possuem servidor HTTP. Para que o Kong retorne respostas HTTP reais nos testes, aponte os services para o `mock-api` (nginx com respostas JSON estáticas):

```bash
curl -s -X PATCH http://localhost:8001/services/users-api  -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/services/catalog-api -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/routes/users-api-public-route   -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/users-api-protected-route -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/catalog-api-route         -d "strip_path=false"
```

---

## Passo 4 — Validar o Ambiente

### Verificar todos os pods

```bash
kubectl get pods -n fcg-tech-fase-2
```

Deve haver **13 pods** todos `Running`:

```
catalog-api-xxxxx       1/1   Running
kong-xxxxx              1/1   Running
kong-database-xxxxx     1/1   Running
konga-xxxxx             1/1   Running
mock-api-xxxxx          1/1   Running
mongodb-xxxxx           1/1   Running
notification-api-xxxxx  1/1   Running
orchestrator-xxxxx      1/1   Running
payments-api-xxxxx      1/1   Running
postgres-xxxxx          1/1   Running
rabbitmq-xxxxx          1/1   Running
sqlserver-xxxxx         1/1   Running
users-api-xxxxx         1/1   Running
```

### Teste rápido das políticas Kong

**PowerShell:**

```powershell
.\k8s\test-kong.ps1
```

**Bash / curl:**

```bash
# Rota pública (sem JWT) — deve retornar 201
curl -s -o /dev/null -w "register: %{http_code}\n" \
  -X POST http://localhost:9080/api/users/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Teste","email":"teste@email.com","password":"senha123"}'

# Rota protegida sem token — deve retornar 401
curl -s -o /dev/null -w "sem-jwt: %{http_code}\n" \
  http://localhost:9080/api/users

# Rota protegida com token — deve retornar 200
JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJVc2Vyc0FQSSIsInN1YiI6InRlc3QtdXNlciIsImlhdCI6MTcxNjAwMDAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.Fb1aktmw8GtBrvfMqxInF9j1GseZhPa1wFhaQY4JPbY"
curl -s -o /dev/null -w "com-jwt: %{http_code}\n" \
  http://localhost:9080/api/users \
  -H "Authorization: Bearer $JWT"
```

Resultado esperado:
```
register: 201
sem-jwt: 401
com-jwt: 200
```

### Teste E2E do fluxo de eventos

```bash
bash k8s/test-e2e.sh
```

---

## Resumo — Todos os Comandos em Sequência

Para uma máquina zerada, sequência completa (copiar e executar em Bash):

```bash
# 1. Deploy base
bash k8s/deploy.sh --destroy

# 2. Deploy Kong
kubectl apply -f k8s/kong-secret.yaml             -n fcg-tech-fase-2
kubectl apply -f k8s/kong-database-deployment.yaml -n fcg-tech-fase-2
kubectl wait --for=condition=ready pod -l app=kong-database -n fcg-tech-fase-2 --timeout=120s
kubectl apply -f k8s/kong-deployment.yaml          -n fcg-tech-fase-2
kubectl apply -f k8s/konga-deployment.yaml         -n fcg-tech-fase-2
kubectl apply -f k8s/mock-api-deployment.yaml      -n fcg-tech-fase-2
kubectl wait --for=condition=ready pod -l app=kong  -n fcg-tech-fase-2 --timeout=120s
kubectl wait --for=condition=ready pod -l app=konga -n fcg-tech-fase-2 --timeout=120s

# 3. Port-forwards (executar em terminais separados)
# kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2
# kubectl port-forward svc/kong-proxy 9080:80   -n fcg-tech-fase-2
# kubectl port-forward svc/konga 1337:1337       -n fcg-tech-fase-2

# 4. Configurar Kong (após abrir port-forward do admin)
bash k8s/kong-setup.sh

# 5. Apontar para mock backend
curl -s -X PATCH http://localhost:8001/services/users-api  -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/services/catalog-api -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/routes/users-api-public-route   -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/users-api-protected-route -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/catalog-api-route         -d "strip_path=false"
```

---

## Referência de Acessos

| Serviço | URL local | Descrição |
|---|---|---|
| Kong Proxy | http://localhost:9080 | Ponto de entrada das APIs |
| Kong Admin API | http://localhost:8001 | Gerenciamento Kong (admin) |
| Konga GUI | http://localhost:1337 | Interface visual para Kong |
| RabbitMQ Management | http://localhost:15672 | Gerenciamento de filas (admin/admin123) |

---

## Referência de Credenciais

| Serviço | Usuário | Senha |
|---|---|---|
| RabbitMQ | `admin` | `admin123` |
| MongoDB | `admin` | `admin123` |
| PostgreSQL (Catalog) | `catalog` | (ver secret) |
| SQL Server | `sa` | (ver secret) |
| Kong Database | `kong` | `kong123` |

**JWT de teste** (HS256, válido até 2286):
```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJVc2Vyc0FQSSIsInN1YiI6InRlc3QtdXNlciIsImlhdCI6MTcxNjAwMDAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.Fb1aktmw8GtBrvfMqxInF9j1GseZhPa1wFhaQY4JPbY
```
Secret: `ChaveSuperSecretaCom32Caracteres!` | Claim `iss`: `UsersAPI`

---

## Estrutura dos Arquivos K8s

```
k8s/
├── 00-namespace.yaml              # Namespace fcg-tech-fase-2
├── deploy.sh                      # Script de deploy completo (base)
├── apply-all.sh                   # Script alternativo de deploy
│
├── # Infraestrutura base
├── mongodb-secret.yaml            # Credenciais MongoDB
├── mongodb-deployment.yaml        # MongoDB + Service
├── postgres-deployment.yaml       # PostgreSQL + Service (Catalog DB)
├── sqlserver-deployment.yaml      # SQL Server + Service (Payments DB)
├── rabbitmq-deployment.yaml       # RabbitMQ + Service
│
├── # Orchestrator
├── orchestrator-secret.yaml       # Secrets do Orchestrator
├── orchestrator-configmap.yaml    # ConfigMap do Orchestrator
├── orchestrator-deployment.yaml   # Deployment do Orchestrator
├── orchestrator-service.yaml      # Service do Orchestrator
│
├── # Microserviços (Workers RabbitMQ, sem HTTP)
├── users-api-deployment.yaml
├── catalog-api-deployment.yaml
├── payments-api-deployment.yaml
├── notification-api-deployment.yaml
│
├── # Kong API Gateway
├── kong-secret.yaml               # Credenciais Kong/Konga DB
├── kong-database-deployment.yaml  # PostgreSQL dedicado Kong+Konga
├── kong-deployment.yaml           # Kong 3.4 (DB mode)
├── kong-configmap.yaml            # Variáveis de ambiente Kong
├── konga-deployment.yaml          # Konga GUI
├── mock-api-deployment.yaml       # nginx mock (testes HTTP)
├── kong-setup.sh                  # Configura rotas/plugins/JWT via Admin API
│
├── # Testes
├── test-e2e.sh                    # Teste E2E fluxo completo
├── test-kong.ps1                  # Testes Kong políticas (PowerShell)
├── postman-kong-collection.json   # Coleção Postman
│
└── README_Kong.md                 # Guia específico do Kong
```

---

## Troubleshooting

### Pod em `CrashLoopBackOff`

```bash
# Ver logs do pod
kubectl logs -l app=<nome-do-pod> -n fcg-tech-fase-2

# Ver logs do init container
kubectl logs -l app=<nome-do-pod> -n fcg-tech-fase-2 -c <nome-init-container>

# Descrever o pod para ver eventos
kubectl describe pod -l app=<nome-do-pod> -n fcg-tech-fase-2
```

### Pod em `Pending` (sem recursos)

```bash
kubectl describe pod <nome-do-pod> -n fcg-tech-fase-2
# Verificar se há "Insufficient memory" ou "Insufficient cpu" nos eventos
```

Solução: Aumentar recursos alocados ao Docker Desktop em **Settings → Resources**.

### Port-forward cai após inatividade

É comportamento normal no Docker Desktop. Basta reexecutar o comando de `port-forward`.

### `deploy.sh` falha com "permission denied"

```bash
chmod +x k8s/deploy.sh k8s/kong-setup.sh k8s/test-e2e.sh k8s/apply-all.sh
```

### Reiniciar o ambiente do zero

```bash
bash k8s/deploy.sh --destroy
```

Isso remove o namespace inteiro e recria tudo. Em seguida, repita os Passos 3 e 4 deste guia.

### Verificar eventos do namespace

```bash
kubectl get events -n fcg-tech-fase-2 --sort-by='.lastTimestamp' | tail -20
```

---

## Testes Unitários e de Integração (.NET)

```bash
# Todos os testes
dotnet test

# Apenas unitários
dotnet test src/Orchestrator.Infrastructure.Tests

# Com output detalhado
dotnet test --verbosity normal
```

Pré-requisito: `.NET 8 SDK` instalado (https://dotnet.microsoft.com/download/dotnet/8.0).
