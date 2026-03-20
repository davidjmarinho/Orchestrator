#!/bin/bash

# Script para testar o Orchestrator publicando eventos no RabbitMQ

POD_NAME=$(kubectl get pods -l app=rabbitmq -o jsonpath='{.items[0].metadata.name}')

echo "🚀 Publicando UserCreatedEvent..."

kubectl exec -it $POD_NAME -- rabbitmqadmin publish \
  exchange=amq.default \
  routing_key=user.created \
  payload='{"UserId":"123","Email":"test@example.com","CreatedAt":"2026-03-20T00:00:00Z"}'

echo ""
echo "📨 Evento publicado na fila user.created"
echo ""
echo "Para verificar logs do orchestrator:"
echo "kubectl logs -f deployment/orchestrator"
