#!/bin/bash

# Script para deploy completo do ecossistema de microserviços
# Autor: Orchestrator Team
# Data: 24 de março de 2026

set -e  # Parar em caso de erro

NAMESPACE="fcg-tech-fase-2"
KUBECTL="kubectl"

echo "=========================================="
echo "  DEPLOY DO ECOSSISTEMA DE MICROSERVIÇOS"
echo "=========================================="
echo ""

# Verificar se o kubectl está instalado
if ! command -v kubectl &> /dev/null; then
    echo "❌ kubectl não encontrado. Por favor, instale o kubectl."
    exit 1
fi

# Verificar contexto do Kubernetes
CURRENT_CONTEXT=$($KUBECTL config current-context)
echo "📍 Contexto atual: $CURRENT_CONTEXT"
echo ""

# Confirmar deploy
read -p "Deseja continuar com o deploy no contexto $CURRENT_CONTEXT? (s/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    echo "❌ Deploy cancelado."
    exit 1
fi

echo ""
echo "🚀 Iniciando deploy..."
echo ""

# Criar namespace se não existir
echo "📦 [1/7] Criando namespace..."
$KUBECTL create namespace $NAMESPACE --dry-run=client -o yaml | $KUBECTL apply -f -
echo "✅ Namespace criado/atualizado"
echo ""

# Deploy de Secrets e ConfigMaps
echo "🔐 [2/7] Aplicando Secrets e ConfigMaps..."
$KUBECTL apply -f orchestrator-secret.yaml
$KUBECTL apply -f mongodb-secret.yaml
$KUBECTL apply -f orchestrator-configmap.yaml
$KUBECTL apply -f postgres-deployment.yaml  # Contém secret e configmap do Postgres
echo "✅ Secrets e ConfigMaps aplicados"
echo ""

# Deploy de Databases
echo "🗄️  [3/7] Deployando bancos de dados..."
$KUBECTL apply -f mongodb-deployment.yaml
$KUBECTL apply -f postgres-deployment.yaml
echo "⏳ Aguardando bancos de dados ficarem prontos..."
$KUBECTL wait --for=condition=ready pod -l app=mongodb -n $NAMESPACE --timeout=120s
$KUBECTL wait --for=condition=ready pod -l app=postgres -n $NAMESPACE --timeout=120s
echo "✅ Bancos de dados prontos"
echo ""

# Deploy de Message Broker
echo "📨 [4/7] Deployando RabbitMQ..."
$KUBECTL apply -f rabbitmq-deployment.yaml
echo "⏳ Aguardando RabbitMQ ficar pronto..."
$KUBECTL wait --for=condition=ready pod -l app=rabbitmq -n $NAMESPACE --timeout=120s
echo "✅ RabbitMQ pronto"
echo ""

# Deploy do Orchestrator
echo "🎯 [5/7] Deployando Orchestrator..."
$KUBECTL apply -f orchestrator-deployment.yaml
$KUBECTL apply -f orchestrator-service.yaml
echo "⏳ Aguardando Orchestrator ficar pronto..."
$KUBECTL wait --for=condition=ready pod -l app=orchestrator -n $NAMESPACE --timeout=120s
echo "✅ Orchestrator pronto"
echo ""

# Deploy das APIs
echo "🔌 [6/7] Deployando microserviços..."
$KUBECTL apply -f users-api-deployment.yaml
$KUBECTL apply -f orders-api-deployment.yaml
$KUBECTL apply -f payments-api-deployment.yaml
$KUBECTL apply -f notification-api-deployment.yaml
$KUBECTL apply -f catalog-api-deployment.yaml
echo "⏳ Aguardando microserviços ficarem prontos..."
sleep 10  # Dar tempo para os pods iniciarem
echo "✅ Microserviços deployados"
echo ""

# Verificar status final
echo "🔍 [7/7] Verificando status dos pods..."
echo ""
$KUBECTL get pods -n $NAMESPACE
echo ""

# Verificar services
echo "🌐 Services disponíveis:"
echo ""
$KUBECTL get services -n $NAMESPACE
echo ""

# Resumo
echo "=========================================="
echo "  ✅ DEPLOY CONCLUÍDO COM SUCESSO!"
echo "=========================================="
echo ""
echo "📊 Comandos úteis:"
echo ""
echo "  # Ver todos os pods"
echo "  kubectl get pods -n $NAMESPACE"
echo ""
echo "  # Ver logs do Orchestrator"
echo "  kubectl logs -f deployment/orchestrator -n $NAMESPACE"
echo ""
echo "  # Acessar RabbitMQ Management"
echo "  kubectl port-forward svc/rabbitmq 15672:15672 -n $NAMESPACE"
echo "  # Abrir: http://localhost:15672"
echo ""
echo "  # Acessar MongoDB"
echo "  kubectl port-forward svc/mongodb 27017:27017 -n $NAMESPACE"
echo ""
echo "  # Testar Users API"
echo "  kubectl port-forward svc/users-api 8001:80 -n $NAMESPACE"
echo "  # Abrir: http://localhost:8001"
echo ""
echo "  # Deletar tudo"
echo "  kubectl delete namespace $NAMESPACE"
echo ""
echo "=========================================="
