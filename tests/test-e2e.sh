#!/bin/bash

echo "🧪 TESTE END-TO-END DO ORCHESTRATOR"
echo "===================================="
echo ""

# Verificar se todos os pods estão running
echo "📊 Verificando status dos pods..."
kubectl get pods -l "app in (orchestrator,rabbitmq,mongodb)" --no-headers | while read line; do
    status=$(echo $line | awk '{print $3}')
    pod=$(echo $line | awk '{print $1}')
    if [ "$status" != "Running" ]; then
        echo "❌ Pod $pod não está Running: $status"
        exit 1
    fi
done

echo "✅ Todos os pods estão Running"
echo ""

# Publicar evento UserCreatedEvent usando Python
echo "📤 Publicando UserCreatedEvent via Python..."
RABBITMQ_POD=$(kubectl get pods -l app=rabbitmq -o jsonpath='{.items[0].metadata.name}')

kubectl exec $RABBITMQ_POD -- python3 -c "
import pika
import json

credentials = pika.PlainCredentials('admin', 'admin123')
connection = pika.BlockingConnection(
    pika.ConnectionParameters('localhost', 5672, '/', credentials)
)
channel = connection.channel()

# Declarar fila
channel.queue_declare(queue='user.created', durable=True)

# Publicar evento
event = {
    'UserId': 'test-123',
    'Email': 'teste@example.com',
    'CreatedAt': '2026-03-20T17:00:00Z'
}

channel.basic_publish(
    exchange='',
    routing_key='user.created',
    body=json.dumps(event),
    properties=pika.BasicProperties(content_type='application/json', delivery_mode=2)
)

print('✅ Evento UserCreatedEvent publicado com sucesso!')
connection.close()
"

# Aguardar processamento
echo "⏳ Aguardando processamento (5 segundos)..."
sleep 5

# Verificar logs do orchestrator
echo ""
echo "📋 Logs do Orchestrator (últimas 20 linhas):"
echo "----------------------------------------"
kubectl logs deployment/orchestrator --tail=20
echo ""

# Verificar MongoDB
echo "🔍 Verificando registros no MongoDB..."
MONGODB_POD=$(kubectl get pods -l app=mongodb -o jsonpath='{.items[0].metadata.name}')

LOG_COUNT=$(kubectl exec $MONGODB_POD -- mongo orchestrator --quiet --eval 'db.Logs.count()' 2>/dev/null)
echo "📊 Total de logs no MongoDB: $LOG_COUNT"
echo ""

if [ "$LOG_COUNT" != "0" ] && [ -n "$LOG_COUNT" ]; then
    echo "📝 Últimos 3 logs:"
    kubectl exec $MONGODB_POD -- mongo orchestrator --quiet --eval '
      db.Logs.find().sort({CreatedAt: -1}).limit(3).forEach(function(doc) {
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        print("ID: " + doc._id);
        print("Event: " + doc.EventName);
        print("Status: " + doc.Status);
        print("Created: " + doc.CreatedAt);
        if (doc.Payload) print("Payload: " + doc.Payload.substring(0, 100));
      })
    ' 2>/dev/null
else
    echo "⚠️  Ainda não há logs no MongoDB"
fi

echo ""
echo "✅ Teste concluído!"
