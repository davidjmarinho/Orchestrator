# Kong API Gateway — Guia de Configuração e Uso

Este guia cobre tudo que um desenvolvedor precisa para subir e configurar o Kong do zero neste projeto.

---

## Visão Geral da Arquitetura

```
Cliente (Postman / Browser)
        │
        ▼  :9080
  ┌──────────────┐
  │  Kong Proxy  │  ← porta 80 interna / 9080 external via port-forward
  └──────┬───────┘
         │  valida JWT, aplica CORS, roteia
         ▼
  ┌──────────────────────────────────────────┐
  │  Rotas Kong                              │
  │                                          │
  │  /api/users/register  →  users-api:80   │  (sem JWT)
  │  /api/users/login     →  users-api:80   │  (sem JWT)
  │  /api/users/**        →  users-api:80   │  (JWT obrigatório)
  │  /api/catalog/**      →  catalog-api:80 │  (JWT obrigatório)
  │  /api/products/**     →  catalog-api:80 │  (JWT obrigatório)
  └──────────────────────────────────────────┘
         │
         ▼
  Workers / Mock Backend (pods K8s)

  Kong Admin API: :8001  ← port-forward para administração
  Konga GUI:      :1337  ← port-forward para interface visual
```

---

## Pré-requisitos

- Docker Desktop com Kubernetes habilitado
- `kubectl` no PATH, contexto apontando para `docker-desktop`
- Ambiente base já deployado (ver `README_Initial.md`)
- Bash (WSL2, Git Bash ou Linux/macOS) **ou** PowerShell para os testes
- `python3` disponível no PATH (usado pelos scripts de output)
- `curl` disponível no PATH

---

## Passo 1 — Deploy da Infraestrutura Kong

Os arquivos YAML sobem o Postgres do Kong, o Kong e a Konga:

```bash
kubectl apply -f k8s/kong-secret.yaml          -n fcg-tech-fase-2
kubectl apply -f k8s/kong-database-deployment.yaml -n fcg-tech-fase-2
```

Aguardar o banco:

```bash
kubectl wait --for=condition=ready pod -l app=kong-database \
  -n fcg-tech-fase-2 --timeout=120s
```

```bash
kubectl apply -f k8s/kong-deployment.yaml  -n fcg-tech-fase-2
kubectl apply -f k8s/konga-deployment.yaml -n fcg-tech-fase-2
kubectl apply -f k8s/mock-api-deployment.yaml -n fcg-tech-fase-2
```

Aguardar Kong e Konga:

```bash
kubectl wait --for=condition=ready pod -l app=kong  -n fcg-tech-fase-2 --timeout=120s
kubectl wait --for=condition=ready pod -l app=konga -n fcg-tech-fase-2 --timeout=120s
```

Verificar pods:

```bash
kubectl get pods -n fcg-tech-fase-2
```

Esperado (relacionados ao Kong):

```
kong-xxxxx              1/1   Running
kong-database-xxxxx     1/1   Running
konga-xxxxx             1/1   Running
mock-api-xxxxx          1/1   Running
```

---

## Passo 2 — Port-Forwards (terminais separados)

Abra **3 terminais** e execute um comando em cada:

```bash
# Terminal 1 — Kong Proxy (requisições de negócio)
kubectl port-forward svc/kong-proxy 9080:80 -n fcg-tech-fase-2

# Terminal 2 — Kong Admin API (configuração via script)
kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2

# Terminal 3 — Konga GUI (opcional, interface visual)
kubectl port-forward svc/konga 1337:1337 -n fcg-tech-fase-2
```

> **Windows PowerShell**: mantenha os 3 terminais abertos enquanto estiver testando.

---

## Passo 3 — Configurar Kong via Script

Com o port-forward da Admin API ativo (Terminal 2), execute:

```bash
bash k8s/kong-setup.sh
```

O script configura automaticamente:

| # | O que cria |
|---|---|
| 1 | Plugin global **CORS** (origens `*`, todos os métodos) |
| 2 | Service `users-api` → `http://users-api:80` |
| 3 | Rota **pública** `/api/users/login` e `/api/users/register` (sem JWT) |
| 4 | Rota **protegida** `/api/users/**` + plugin JWT |
| 5 | Service `catalog-api` → `http://catalog-api:80` |
| 6 | Rota **protegida** `/api/catalog/**` e `/api/products/**` + plugin JWT |
| 7 | Consumer `app-consumer` |
| 8 | Credencial JWT HS256, key=`UsersAPI`, secret=`ChaveSuperSecretaCom32Caracteres!` |

### Verificar configuração aplicada

```bash
# Listar services
curl -s http://localhost:8001/services | python3 -c "import sys,json; [print(s['name'],'->',s['host']+':'+str(s['port'])) for s in json.load(sys.stdin)['data']]"

# Listar rotas
curl -s http://localhost:8001/routes | python3 -c "import sys,json; [print(r['name'], r.get('paths')) for r in json.load(sys.stdin)['data']]"

# Listar plugins
curl -s "http://localhost:8001/plugins?size=100" | python3 -c "import sys,json; [print(p['name'], '->', p.get('route',{}).get('id','global') if p.get('route') else 'global') for p in json.load(sys.stdin)['data']]"

# Listar credenciais JWT do consumer
curl -s http://localhost:8001/consumers/app-consumer/jwt | python3 -c "import sys,json; [print('key:',c['key'],'algo:',c['algorithm']) for c in json.load(sys.stdin)['data']]"
```

---

## Passo 4 — Apontar Kong para Mock Backend (testes locais)

Os pods `users-api` e `catalog-api` são Workers RabbitMQ (sem HTTP). Para testar as políticas do Kong com respostas HTTP reais, aponte os services para o `mock-api`:

```bash
curl -s -X PATCH http://localhost:8001/services/users-api  -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/services/catalog-api -d "url=http://mock-api:80"
```

Para desabilitar o `strip_path` nas rotas (necessário para o nginx receber o path completo):

```bash
curl -s -X PATCH http://localhost:8001/routes/users-api-public-route   -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/users-api-protected-route -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/catalog-api-route         -d "strip_path=false"
```

---

## Passo 5 — Testar as Políticas

### Opção A — Script PowerShell automatizado

```powershell
.\k8s\test-kong.ps1
# ou especificando a porta:
.\k8s\test-kong.ps1 -KongUrl http://localhost:9080
```

### Opção B — curl manual

**Token JWT pré-computado** (válido até 2286):

```
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJVc2Vyc0FQSSIsInN1YiI6InRlc3QtdXNlciIsImlhdCI6MTcxNjAwMDAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.Fb1aktmw8GtBrvfMqxInF9j1GseZhPa1wFhaQY4JPbY
```

```bash
# 1. Rota pública — deve retornar 201 (sem JWT)
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:9080/api/users/register \
  -H "Content-Type: application/json" \
  -d '{"name":"Teste","email":"teste@email.com","password":"senha123"}'
# Esperado: 201

# 2. Rota pública login — deve retornar 200 (sem JWT)
curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:9080/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"teste@email.com","password":"senha123"}'
# Esperado: 200

# 3. Rota protegida SEM token — deve retornar 401
curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/api/users
# Esperado: 401

# 4. Rota protegida COM token válido — deve retornar 200
JWT="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJVc2Vyc0FQSSIsInN1YiI6InRlc3QtdXNlciIsImlhdCI6MTcxNjAwMDAwMCwiZXhwIjo5OTk5OTk5OTk5fQ.Fb1aktmw8GtBrvfMqxInF9j1GseZhPa1wFhaQY4JPbY"

curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/api/users \
  -H "Authorization: Bearer $JWT"
# Esperado: 200

curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/api/catalog \
  -H "Authorization: Bearer $JWT"
# Esperado: 200

curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/api/products \
  -H "Authorization: Bearer $JWT"
# Esperado: 200

# 5. Token inválido — deve retornar 401
curl -s -o /dev/null -w "%{http_code}" http://localhost:9080/api/users \
  -H "Authorization: Bearer token-invalido"
# Esperado: 401
```

### Opção C — Postman

Importe o arquivo [postman-kong-collection.json](postman-kong-collection.json).

A coleção já inclui:
- Geração automática de JWT via CryptoJS (HS256, `iss=UsersAPI`)
- Variável `base_url` = `http://localhost:9080`
- Pastas: Rotas Públicas, Rotas Protegidas (JWT válido), Verificação Auth (401), CORS

---

## Referência de Configuração Kong

### Services

| Nome | Upstream atual |
|---|---|
| `users-api` | `http://mock-api:80` (testes) / `http://users-api:80` (produção) |
| `catalog-api` | `http://mock-api:80` (testes) / `http://catalog-api:80` (produção) |

### Rotas

| Nome | Paths | JWT | Métodos |
|---|---|---|---|
| `users-api-public-route` | `/api/users/login$`, `/api/users/register$` (regex) | ❌ | GET, POST, OPTIONS |
| `users-api-protected-route` | `/api/users` | ✅ | Todos |
| `catalog-api-route` | `/api/catalog`, `/api/products` | ✅ | Todos |

### Plugins

| Plugin | Escopo | Config |
|---|---|---|
| `cors` | Global | `origins: *`, todos os métodos |
| `jwt` | `users-api-protected-route` | HS256, `iss` claim |
| `jwt` | `catalog-api-route` | HS256, `iss` claim |

### Consumer + Credencial JWT

| Campo | Valor |
|---|---|
| Consumer | `app-consumer` |
| Algoritmo | `HS256` |
| Key (`iss`) | `UsersAPI` |
| Secret | `ChaveSuperSecretaCom32Caracteres!` |

### Exemplo de payload JWT

```json
{
  "iss": "UsersAPI",
  "sub": "user-id",
  "iat": 1716000000,
  "exp": 9999999999
}
```

---

## Konga — Interface Visual

Acesse: **http://localhost:1337**

1. Crie uma conta de administrador (primeiro acesso)
2. Vá em **Connections** → **New Connection**
   - Nome: `local`
   - Kong Admin URL: `http://kong:8001`
3. Clique em **Activate**

---

## Troubleshooting

### `curl: (7) Failed to connect to localhost port 8001`
Port-forward do Admin não está ativo. Execute:
```bash
kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2
```

### `curl: (7) Failed to connect to localhost port 9080`
Port-forward do Proxy não está ativo. Execute:
```bash
kubectl port-forward svc/kong-proxy 9080:80 -n fcg-tech-fase-2
```

### Retorna `{"message":"An unexpected error occurred"}` (HTTP 500)
Kong não consegue se conectar ao upstream. Verifique:
```bash
# Ver para onde o Kong está apontando
curl -s http://localhost:8001/services/users-api | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['host'], d['port'])"

# Se o upstream for os workers reais (sem HTTP), redirecionar para mock:
curl -s -X PATCH http://localhost:8001/services/users-api  -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/services/catalog-api -d "url=http://mock-api:80"
```

### Retorna `401` mesmo com token válido
Verifique se a credencial JWT foi criada corretamente:
```bash
curl -s http://localhost:8001/consumers/app-consumer/jwt
```
Confirme que `key = UsersAPI` e `algorithm = HS256`.

### `kong-setup.sh` falha com `command not found: python3`
Substitua `python3` por `python` no script, ou instale Python 3.

### Kong pod em `CrashLoopBackOff`
O banco do Kong pode não ter sido inicializado:
```bash
kubectl logs -l app=kong -n fcg-tech-fase-2 --previous
kubectl logs -l app=kong-database -n fcg-tech-fase-2
```

---

## Restaurar Estado Completo (após reinício do cluster)

Execute na ordem:

```bash
# 1. Verificar se o namespace existe
kubectl get namespace fcg-tech-fase-2

# 2. Aplicar YAMLs do Kong (se ainda não aplicados)
kubectl apply -f k8s/kong-secret.yaml -n fcg-tech-fase-2
kubectl apply -f k8s/kong-database-deployment.yaml -n fcg-tech-fase-2
kubectl apply -f k8s/kong-deployment.yaml -n fcg-tech-fase-2
kubectl apply -f k8s/konga-deployment.yaml -n fcg-tech-fase-2
kubectl apply -f k8s/mock-api-deployment.yaml -n fcg-tech-fase-2

# 3. Aguardar pods
kubectl wait --for=condition=ready pod -l app=kong -n fcg-tech-fase-2 --timeout=120s

# 4. Abrir port-forward Admin (em terminal separado)
kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2

# 5. Recriar toda a configuração
bash k8s/kong-setup.sh

# 6. Apontar para mock (para testes)
curl -s -X PATCH http://localhost:8001/services/users-api  -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/services/catalog-api -d "url=http://mock-api:80"
curl -s -X PATCH http://localhost:8001/routes/users-api-public-route   -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/users-api-protected-route -d "strip_path=false"
curl -s -X PATCH http://localhost:8001/routes/catalog-api-route         -d "strip_path=false"

# 7. Abrir port-forward Proxy (em terminal separado)
kubectl port-forward svc/kong-proxy 9080:80 -n fcg-tech-fase-2
```
