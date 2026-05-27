# 📂 Estrutura de Manifestos Kubernetes

Este diretório contém todos os manifestos necessários para deployar o **ecossistema completo de microserviços** no Kubernetes.

## 📋 Arquivos

### 🗄️ Bancos de Dados
- **mongodb-deployment.yaml** - MongoDB para logs do Orchestrator
- **mongodb-secret.yaml** - Credenciais do MongoDB
- **postgres-deployment.yaml** - PostgreSQL para as APIs + Secret e ConfigMap

### 📨 Message Broker
- **rabbitmq-deployment.yaml** - RabbitMQ Deployment + Service

### 🎯 Orchestrator
- **orchestrator-deployment.yaml** - Deployment do Orchestrator
- **orchestrator-service.yaml** - Service do Orchestrator
- **orchestrator-configmap.yaml** - Configurações do Orchestrator
- **orchestrator-secret.yaml** - Credenciais RabbitMQ

### 🔌 Microserviços (APIs)
- **users-api-deployment.yaml** - Users API (Deployment + Service)
- **orders-api-deployment.yaml** - Orders API (Deployment + Service)
- **payments-api-deployment.yaml** - Payments API (Deployment + Service)
- **notification-api-deployment.yaml** - Notification API (Deployment + Service)
- **catalog-api-deployment.yaml** - Catalog API (Deployment + Service)

### 🚀 Scripts
- **apply-all.sh** - Script automatizado para deploy completo

---

## 🚀 Deploy Rápido

### Opção 1: Script Automatizado (Recomendado)

```bash
cd k8s/
./apply-all.sh
```

O script irá:
1. ✅ Criar o namespace `fcg-tech-fase-2`
2. ✅ Aplicar Secrets e ConfigMaps
3. ✅ Deployar MongoDB e PostgreSQL
4. ✅ Deployar RabbitMQ
5. ✅ Deployar Orchestrator
6. ✅ Deployar todos os microserviços
7. ✅ Aguardar pods ficarem prontos
8. ✅ Mostrar status final

---

### Opção 2: Manual (Passo a Passo)

```bash
# 1. Criar namespace
kubectl create namespace fcg-tech-fase-2

# 2. Aplicar Secrets e ConfigMaps
kubectl apply -f orchestrator-secret.yaml
kubectl apply -f mongodb-secret.yaml
kubectl apply -f orchestrator-configmap.yaml

# 3. Deployar Bancos de Dados
kubectl apply -f mongodb-deployment.yaml
kubectl apply -f postgres-deployment.yaml

# 4. Aguardar bancos estarem prontos
kubectl wait --for=condition=ready pod -l app=mongodb -n fcg-tech-fase-2 --timeout=120s
kubectl wait --for=condition=ready pod -l app=postgres -n fcg-tech-fase-2 --timeout=120s

# 5. Deployar RabbitMQ
kubectl apply -f rabbitmq-deployment.yaml
kubectl wait --for=condition=ready pod -l app=rabbitmq -n fcg-tech-fase-2 --timeout=120s

# 6. Deployar Orchestrator
kubectl apply -f orchestrator-deployment.yaml
kubectl apply -f orchestrator-service.yaml
kubectl wait --for=condition=ready pod -l app=orchestrator -n fcg-tech-fase-2 --timeout=120s

# 7. Deployar Microserviços
kubectl apply -f users-api-deployment.yaml
kubectl apply -f orders-api-deployment.yaml
kubectl apply -f payments-api-deployment.yaml
kubectl apply -f notification-api-deployment.yaml
kubectl apply -f catalog-api-deployment.yaml

# 8. Verificar todos os pods
kubectl get pods -n fcg-tech-fase-2
```

---

### Opção 3: Apply Direto (Todos de uma vez)

```bash
kubectl apply -f k8s/
```

⚠️ **Atenção**: Esta opção não aguarda dependências, então pode haver erros de inicialização temporários até todos os serviços subirem.

---

## 🔍 Verificação

### Ver todos os pods

```bash
kubectl get pods -n fcg-tech-fase-2
```

**Saída esperada:**
```
NAME                               READY   STATUS    RESTARTS   AGE
catalog-api-xxxxxxxxxx-xxxxx       1/1     Running   0          2m
mongodb-xxxxxxxxxx-xxxxx           1/1     Running   0          5m
notification-api-xxxxxxxxxx-xxxxx  1/1     Running   0          2m
orchestrator-xxxxxxxxxx-xxxxx      1/1     Running   0          3m
orders-api-xxxxxxxxxx-xxxxx        1/1     Running   0          2m
payments-api-xxxxxxxxxx-xxxxx      1/1     Running   0          2m
postgres-xxxxxxxxxx-xxxxx          1/1     Running   0          5m
rabbitmq-xxxxxxxxxx-xxxxx          1/1     Running   0          4m
users-api-xxxxxxxxxx-xxxxx         1/1     Running   0          2m
```

### Ver services

```bash
kubectl get services -n fcg-tech-fase-2
```

### Ver logs de um serviço

```bash
# Orchestrator
kubectl logs -f deployment/orchestrator -n fcg-tech-fase-2

# Users API
kubectl logs -f deployment/users-api -n fcg-tech-fase-2

# Orders API
kubectl logs -f deployment/orders-api -n fcg-tech-fase-2
```

---

## 🌐 Acessando os Serviços

### RabbitMQ Management

```bash
kubectl port-forward svc/rabbitmq 15672:15672 -n fcg-tech-fase-2
```
Abrir: http://localhost:15672

### MongoDB

```bash
kubectl port-forward svc/mongodb 27017:27017 -n fcg-tech-fase-2
```
Connection string: `mongodb://localhost:27017`

### PostgreSQL

```bash
kubectl port-forward svc/postgres 5432:5432 -n fcg-tech-fase-2
```
Connection: `postgresql://localhost:5432`

### APIs

```bash
# Users API
kubectl port-forward svc/users-api 8001:80 -n fcg-tech-fase-2
# http://localhost:8001

# Orders API
kubectl port-forward svc/orders-api 8002:80 -n fcg-tech-fase-2
# http://localhost:8002

# Payments API
kubectl port-forward svc/payments-api 8003:80 -n fcg-tech-fase-2
# http://localhost:8003

# Notification API
kubectl port-forward svc/notification-api 8004:80 -n fcg-tech-fase-2
# http://localhost:8004

# Catalog API
kubectl port-forward svc/catalog-api 8005:80 -n fcg-tech-fase-2
# http://localhost:8005
```

---

## 🔄 Atualizações

### Atualizar um deployment

```bash
# Rebuild e push da imagem
docker build -t davidjmarinho/users-api:v2 .
docker push davidjmarinho/users-api:v2

# Atualizar no Kubernetes
kubectl set image deployment/users-api \
  users-api=davidjmarinho/users-api:v2 \
  -n fcg-tech-fase-2

# Verificar rollout
kubectl rollout status deployment/users-api -n fcg-tech-fase-2
```

### Rollback

```bash
kubectl rollout undo deployment/users-api -n fcg-tech-fase-2
```

---

## 🗑️ Limpeza

### Deletar tudo

```bash
kubectl delete namespace fcg-tech-fase-2
```

### Deletar serviços específicos

```bash
# Deletar uma API
kubectl delete -f users-api-deployment.yaml

# Deletar o Orchestrator
kubectl delete -f orchestrator-deployment.yaml
kubectl delete -f orchestrator-service.yaml

# Deletar RabbitMQ
kubectl delete -f rabbitmq-deployment.yaml
```

---

## ⚠️ Notas Importantes

### 1. Imagens Docker

As APIs estão configuradas com uma imagem de exemplo:
```yaml
image: mcr.microsoft.com/dotnet/samples:aspnetapp
```

**Você precisa substituir** por suas imagens reais:

```yaml
# Users API
image: davidjmarinho/users-api:v1

# Orders API
image: davidjmarinho/orders-api:v1

# Payments API
image: davidjmarinho/payments-api:v1

# etc.
```

### 2. Health Checks

Todos os deployments têm health checks configurados:
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 80
```

**Certifique-se** de implementar o endpoint `/health` em cada API!

### 3. Resources

Recursos configurados por padrão:
- **Requests**: 128Mi RAM, 100m CPU
- **Limits**: 256Mi RAM, 200m CPU

Ajuste conforme necessário para produção.

### 4. Secrets

As senhas estão em base64. Para alterá-las:

```bash
# Gerar nova senha em base64
echo -n "nova-senha" | base64

# Atualizar o secret
kubectl edit secret rabbitmq-secret -n fcg-tech-fase-2
```

---

## 📊 Arquitetura Deployada

```
┌─────────────────────────────────────────────────────────────┐
│                    KUBERNETES CLUSTER                        │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    NAMESPACE                          │  │
│  │                fcg-tech-fase-2                        │  │
│  │                                                       │  │
│  │  🔌 APIs (5 pods)                                    │  │
│  │    ├── users-api                                     │  │
│  │    ├── orders-api                                    │  │
│  │    ├── payments-api                                  │  │
│  │    ├── notification-api                              │  │
│  │    └── catalog-api                                   │  │
│  │                 │                                     │  │
│  │                 ▼                                     │  │
│  │  📨 RabbitMQ (1 pod)                                 │  │
│  │                 │                                     │  │
│  │                 ▼                                     │  │
│  │  🎯 Orchestrator (1 pod)                             │  │
│  │                 │                                     │  │
│  │       ┌─────────┴─────────┐                          │  │
│  │       ▼                   ▼                          │  │
│  │  📨 RabbitMQ         💾 MongoDB                      │  │
│  │  (publish)           (logs)                          │  │
│  │                                                       │  │
│  │  🗄️  PostgreSQL (1 pod)                              │  │
│  │     └── usersdb, ordersdb, paymentsdb, etc          │  │
│  │                                                       │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Fluxo de Deploy

```
1. Secrets/ConfigMaps
   ↓
2. Databases (MongoDB + PostgreSQL)
   ↓
3. RabbitMQ
   ↓
4. Orchestrator
   ↓
5. Microservices (APIs)
```

Esta ordem garante que as dependências estejam prontas antes de cada serviço iniciar.

---

## 📚 Referências

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Docker Hub - davidjmarinho](https://hub.docker.com/u/davidjmarinho)
- [RabbitMQ on Kubernetes](https://www.rabbitmq.com/kubernetes/operator/operator-overview.html)
- [MongoDB on Kubernetes](https://docs.mongodb.com/kubernetes-operator/)

---

**Desenvolvido com ❤️ pela equipe Orchestrator**
