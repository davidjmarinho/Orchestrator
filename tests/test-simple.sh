#!/bin/bash
# Teste simples do Orchestrator usando RabbitMQ Management API
# Requer: kubectl port-forward svc/rabbitmq 15672:15672

echo "🧪 TESTE SIMPLES DO ORCHESTRATOR"
echo "================================="
echo ""

# Verificar porta 15672
if ! nc -z localhost 15672 2>/dev/null; then
    echo "⚠️  Port-forward não detectado. Executando..."
    kubectl port-forward svc/rabbitmq 15672:15672 &
    PF_PID=$!
    sleep 3
fi

# Publicar UserCreatedEvent
echo "📤 Publicando UserCreatedEvent..."
curl -s -u admin:admin123 -X POST \
  http://localhost:15672/api/exchanges/%2F/amq.default/publish \
  -H 'Content-Type: application/json' \
  -d '{
    "properties": {
      "content_type": "application/json",
      "delivery_mode": 2
    },
    "routing_key": "user.created",
    "payload": "{\"UserId\":\"test-123\",\"Email\":\"teste@example.com\",\"CreatedAt\":\"2026-03-20T17:00:00Z\"}",
    "payload_encoding": "string"
  }' | jq -r '.routed'

if [ $? -eq 0 ]; then
    echo "✅ Evento publicado"
else
    echo "❌ Erro ao publicar evento"
fi

echo ""
echo "⏳ Aguardando processamento (3 segundos)..."
sleep 3

echo ""
echo "📋 Logs do Orchestrator:"
kubectl logs deployment/orchestrator --tail=15

echo ""
echo "✅ Teste concluído!"
echo ""
echo "💡 Para ver interface web: http://localhost:15672 (admin/admin123)"

# Cleanup
if [ -n "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null
fi
