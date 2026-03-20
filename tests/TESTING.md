# Testando o Orchestrator no Kubernetes

## ✅ Status Atual

- **Orchestrator**: Rodando em Kubernetes
- **RabbitMQ**: Rodando com credenciais admin/admin123
- **MongoDB**: Rodando para persistência de logs

## 🧪 Como Testar

### 1. **Via Interface Web do RabbitMQ**

```bash
kubectl port-forward svc/rabbitmq 15672:15672
```

Acesse: **http://localhost:15672**
- **Usuário**: admin
- **Senha**: admin123

No RabbitMQ Management:
1. Vá em **Queues** → Clique em `orchestrator-queue`
2. Em **Publish message**, cole o JSON:

```json
{
  "UserId": "test-123",
  "Email": "teste@example.com",
  "CreatedAt": "2026-03-20T17:00:00Z"
}
```

3. Clique em **Publish message**

### 2. **Via Linha de Comando**

```bash
# Abrir port-forward
kubectl port-forward svc/rabbitmq 15672:15672 &

# Publicar evento
curl -u admin:admin123 -X POST \
  http://localhost:15672/api/exchanges/%2F/amq.default/publish \
  -H 'Content-Type: application/json' \
  -d '{
    "routing_key": "orchestrator-queue",
    "payload": "{\"UserId\":\"test-123\",\"Email\":\"teste@example.com\"}",
    "properties": {"delivery_mode": 2, "content_type": "application/json"},
    "payload_encoding": "string"
  }'
```

### 3. **Monitorar Logs do Orchestrator**

```bash
kubectl logs -f deployment/orchestrator
```

Você deve ver:
```
info: Microsoft.Hosting.Lifetime[0]
      Application started. Press Ctrl+C to shut down.
```

### 4. **Verificar Logs no MongoDB**

```bash
# Port-forward para MongoDB
kubectl port-forward svc/mongodb 27017:27017 &

# Conectar e verificar logs
mongo mongodb://localhost:27017/orchestrator --eval "db.Logs.find().pretty()"
```

## 📦 Filas Configuradas

O Orchestrator atualmente consome da fila:
- `orchestrator-queue`

Para usar as filas específicas de eventos (`user.created`, `order.placed`, `payment.processed`), é necessário atualizar o código do `RabbitMqHostedService.cs`.

## 🔍 Comandos Úteis

```bash
# Ver todos os pods
kubectl get pods

# Ver logs do orchestrator
kubectl logs deployment/orchestrator --tail=50

# Ver logs do RabbitMQ
kubectl logs deployment/rabbitmq --tail=50

# Acessar pod do orchestrator
kubectl exec -it deployment/orchestrator -- /bin/bash

# Descrever deployment
kubectl describe deployment orchestrator

# Reiniciar orchestrator
kubectl rollout restart deployment/orchestrator
```

## 🐛 Troubleshooting

### Orchestrator não está processando mensagens

1. Verificar se está rodando:
```bash
kubectl get pods -l app=orchestrator
```

2. Ver logs para erros:
```bash
kubectl logs deployment/orchestrator
```

3. Verificar conectividade com RabbitMQ:
```bash
kubectl exec deployment/orchestrator -- ping rabbitmq -c 3
```

### RabbitMQ com erro de autenticação

Verificar secret:
```bash
kubectl get secret rabbitmq-secret -o yaml
```

As credenciais em base64:
- `YWRtaW4=` = admin
- `YWRtaW4xMjM=` = admin123

## 📊 Teste Automatizado

Execute o script de teste:
```bash
./tests/test-simple.sh
```

Este script:
1. Verifica se os pods estão rodando
2. Publica um evento de teste
3. Mostra os logs do orchestrator
