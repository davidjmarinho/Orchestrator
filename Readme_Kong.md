# Kong API Gateway — Guia de Acesso

## Visão Geral

O Kong atua como único ponto de entrada para requisições externas no cluster `fcg-tech-fase-2`.  
Valida tokens JWT e roteia as requisições para os microserviços internos.

```
Cliente → Kong Proxy (:8080) → users-api / catalog-api
```

---

## Pré-requisitos

- Cluster Kubernetes em execução (`kubectl config use-context docker-desktop`)
- Todos os pods com status `Running` (`kubectl get pods -n fcg-tech-fase-2`)

---

## Expondo os serviços (port-forward)

Abra **terminais separados** para cada serviço:

### Kong Proxy — ponto de entrada das APIs
```powershell
kubectl port-forward svc/kong-proxy 8080:80 -n fcg-tech-fase-2
```
Acesso: `http://localhost:8080`

### Kong Manager — interface gráfica
```powershell
# 1. Obter o nome do pod Kong
kubectl get pods -l app=kong -n fcg-tech-fase-2

# 2. Substituir <nome-do-pod> pelo valor retornado
kubectl port-forward pod/<nome-do-pod> 8002:8002 -n fcg-tech-fase-2
```
Acesso: `http://localhost:8002`

### Kong Admin API — API REST de administração
```powershell
kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2
```
Acesso: `http://localhost:8001`

---

## Rotas configuradas

| Método | Caminho | Autenticação | Destino |
|--------|---------|-------------|---------|
| POST | `/api/users/login` | Pública | `users-api` |
| POST | `/api/users/register` | Pública | `users-api` |
| * | `/api/users/**` | JWT obrigatório | `users-api` |
| * | `/api/catalog/**` | JWT obrigatório | `catalog-api` |
| * | `/api/products/**` | JWT obrigatório | `catalog-api` |

---

## Testando via Postman / Insomnia

### 1. Obter token (rota pública)
```http
POST http://localhost:8080/api/users/login
Content-Type: application/json

{
  "email": "usuario@email.com",
  "password": "senha123"
}
```

### 2. Usar token nas rotas protegidas
```http
GET http://localhost:8080/api/users
Authorization: Bearer <token_retornado_no_login>
```

### Sem token — resposta esperada (401)
```http
GET http://localhost:8080/api/catalog
# Retorna: HTTP 401 Unauthorized
```

---

## Kong Manager (interface gráfica)

Acesse `http://localhost:8002` após o port-forward do pod Kong.

Na interface é possível visualizar:
- **Services** — `users-api` e `catalog-api` configurados
- **Routes** — rotas públicas e protegidas
- **Plugins** — JWT e CORS ativos
- **Consumers** — `app-consumer` com credencial JWT HS256

---

## Admin API — consultas úteis

```powershell
# Listar serviços
curl http://localhost:8001/services

# Listar rotas
curl http://localhost:8001/routes

# Listar plugins ativos
curl http://localhost:8001/plugins

# Listar consumers
curl http://localhost:8001/consumers

# Status do Kong
curl http://localhost:8001/status
```

---

## Configuração JWT

| Parâmetro | Valor |
|-----------|-------|
| Algoritmo | HS256 |
| Issuer (`iss`) | `UsersAPI` |
| Secret | `ChaveSuperSecretaCom32Caracteres!` |
| Consumer | `app-consumer` |

O token JWT deve ser gerado pela **UsersAPI** e enviado no header `Authorization: Bearer <token>`.

---

## Arquivos de configuração

| Arquivo | Descrição |
|---------|-----------|
| `kong-configmap.yaml` | Configuração declarativa do Kong (rotas, plugins, consumers) |
| `kong-deployment.yaml` | Deployment + Services (proxy, admin, manager) |

---

## Imagem utilizada

```
kong/kong-gateway:3.4
```
> Inclui Kong Manager (GUI) no Free Mode sem necessidade de licença.
