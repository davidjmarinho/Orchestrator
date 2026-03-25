#!/bin/bash
#═══════════════════════════════════════════════════════════════════
# 🚀 FCG Tech - Deploy Completo do Ecossistema
#═══════════════════════════════════════════════════════════════════
# Este script faz o deploy de TODA a infraestrutura e microserviços
# com um único comando. Nenhuma intervenção manual é necessária.
#
# Uso:
#   ./deploy.sh              # Deploy completo
#   ./deploy.sh --destroy    # Remove tudo e recria do zero
#   ./deploy.sh --delete     # Apenas remove tudo
#   ./deploy.sh --status     # Mostra o status atual
#═══════════════════════════════════════════════════════════════════

set -e

NAMESPACE="fcg-tech-fase-2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ─── Funções auxiliares ───────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════${NC}"
}

print_step() {
    echo -e "\n${BLUE}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

wait_for_pod() {
    local label=$1
    local timeout=${2:-120}
    print_step "Aguardando pod $label ficar Ready (timeout: ${timeout}s)..."
    if kubectl wait --for=condition=ready pod -l app="$label" -n "$NAMESPACE" --timeout="${timeout}s" 2>/dev/null; then
        print_success "$label está pronto!"
    else
        print_warning "$label ainda não está Ready, continuando..."
    fi
}

wait_for_deployment() {
    local name=$1
    local timeout=${2:-120}
    print_step "Aguardando deployment $name (timeout: ${timeout}s)..."
    if kubectl wait --for=condition=available deployment/"$name" -n "$NAMESPACE" --timeout="${timeout}s" 2>/dev/null; then
        print_success "Deployment $name disponível!"
    else
        print_warning "Deployment $name ainda não está disponível, continuando..."
    fi
}

show_status() {
    print_header "📊 Status do Ecossistema"
    echo ""
    echo -e "${YELLOW}Pods:${NC}"
    kubectl get pods -n "$NAMESPACE" -o wide 2>/dev/null || echo "Namespace não encontrado"
    echo ""
    echo -e "${YELLOW}Services:${NC}"
    kubectl get svc -n "$NAMESPACE" 2>/dev/null || echo "Namespace não encontrado"
    echo ""
    echo -e "${YELLOW}Deployments:${NC}"
    kubectl get deployments -n "$NAMESPACE" 2>/dev/null || echo "Namespace não encontrado"
}

delete_all() {
    print_header "🗑️  Removendo todo o ecossistema"
    
    if kubectl get namespace "$NAMESPACE" &>/dev/null; then
        print_step "Deletando namespace $NAMESPACE e todos os recursos..."
        kubectl delete namespace "$NAMESPACE" --timeout=120s 2>/dev/null || true
        
        # Aguardar namespace ser removido
        print_step "Aguardando namespace ser removido..."
        while kubectl get namespace "$NAMESPACE" &>/dev/null; do
            sleep 2
        done
        print_success "Namespace $NAMESPACE removido!"
    else
        print_warning "Namespace $NAMESPACE não existe"
    fi

    # Limpar recursos sem namespace (se houver)
    kubectl delete deployment mongodb orchestrator --ignore-not-found=true 2>/dev/null || true
    kubectl delete svc mongodb orchestrator --ignore-not-found=true 2>/dev/null || true
    kubectl delete secret mongodb-secret rabbitmq-secret --ignore-not-found=true 2>/dev/null || true
    kubectl delete configmap orchestrator-config --ignore-not-found=true 2>/dev/null || true
    
    print_success "Limpeza concluída!"
}

deploy_all() {
    print_header "🚀 FCG Tech - Deploy Completo"
    echo -e "${YELLOW}Namespace: ${NAMESPACE}${NC}"
    echo -e "${YELLOW}Diretório: ${SCRIPT_DIR}${NC}"
    
    # ─── 1. Criar namespace ──────────────────────────────────────
    print_header "1️⃣  Criando Namespace"
    kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    print_success "Namespace $NAMESPACE configurado"

    # ─── 2. Secrets ──────────────────────────────────────────────
    print_header "2️⃣  Aplicando Secrets"
    
    # Secrets que não tem namespace definido
    kubectl apply -f "$SCRIPT_DIR/mongodb-secret.yaml" -n "$NAMESPACE"
    kubectl apply -f "$SCRIPT_DIR/orchestrator-secret.yaml" -n "$NAMESPACE"
    
    # Secret do SQL Server (já tem namespace no yaml)
    kubectl apply -f "$SCRIPT_DIR/sqlserver-deployment.yaml" --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || kubectl apply -f "$SCRIPT_DIR/sqlserver-deployment.yaml"
    
    # Secret e ConfigMap do PostgreSQL (já tem namespace no yaml)
    kubectl apply -f "$SCRIPT_DIR/postgres-deployment.yaml"
    
    print_success "Secrets aplicados"

    # ─── 3. ConfigMaps ───────────────────────────────────────────
    print_header "3️⃣  Aplicando ConfigMaps"
    kubectl apply -f "$SCRIPT_DIR/orchestrator-configmap.yaml" -n "$NAMESPACE"
    print_success "ConfigMaps aplicados"

    # ─── 4. Databases ────────────────────────────────────────────
    print_header "4️⃣  Deploy dos Bancos de Dados"
    
    print_step "Iniciando MongoDB..."
    kubectl apply -f "$SCRIPT_DIR/mongodb-deployment.yaml" -n "$NAMESPACE"
    
    print_step "Iniciando PostgreSQL (com init scripts automáticos)..."
    kubectl apply -f "$SCRIPT_DIR/postgres-deployment.yaml"
    
    print_step "Iniciando SQL Server..."
    kubectl apply -f "$SCRIPT_DIR/sqlserver-deployment.yaml"
    
    # Aguardar bancos ficarem prontos
    wait_for_pod "mongodb" 90
    wait_for_pod "postgres" 90
    wait_for_pod "sqlserver" 120

    print_success "Bancos de dados prontos!"

    # ─── 5. Message Broker ───────────────────────────────────────
    print_header "5️⃣  Deploy do RabbitMQ"
    kubectl apply -f "$SCRIPT_DIR/rabbitmq-deployment.yaml" -n "$NAMESPACE"
    wait_for_pod "rabbitmq" 90
    print_success "RabbitMQ pronto!"

    # ─── 6. Orchestrator ─────────────────────────────────────────
    print_header "6️⃣  Deploy do Orchestrator"
    kubectl apply -f "$SCRIPT_DIR/orchestrator-deployment.yaml" -n "$NAMESPACE"
    kubectl apply -f "$SCRIPT_DIR/orchestrator-service.yaml" -n "$NAMESPACE"
    wait_for_deployment "orchestrator" 90
    print_success "Orchestrator pronto!"

    # ─── 7. Microserviços ────────────────────────────────────────
    print_header "7️⃣  Deploy dos Microserviços"
    echo -e "${YELLOW}Os init containers aguardam automaticamente os bancos e RabbitMQ${NC}"
    
    print_step "Iniciando Users API..."
    kubectl apply -f "$SCRIPT_DIR/users-api-deployment.yaml"
    
    print_step "Iniciando Payments API..."
    kubectl apply -f "$SCRIPT_DIR/payments-api-deployment.yaml"
    
    print_step "Iniciando Catalog API..."
    kubectl apply -f "$SCRIPT_DIR/catalog-api-deployment.yaml"
    
    print_step "Iniciando Notification API..."
    kubectl apply -f "$SCRIPT_DIR/notification-api-deployment.yaml"
    
    # Aguardar microserviços
    print_step "Aguardando microserviços iniciarem (init containers + migrations)..."
    wait_for_deployment "users-api" 180
    wait_for_deployment "payments-api" 180
    wait_for_deployment "catalog-api" 180
    wait_for_deployment "notification-api" 180

    # ─── 8. Catalog DB Tables ────────────────────────────────────
    print_header "8️⃣  Criando tabelas do Catalog API"
    print_step "Aguardando catalog database ficar acessível..."
    local retries=0
    while ! kubectl exec deployment/postgres -n "$NAMESPACE" -- psql -U catalog -d fcg_catalog_db -c "SELECT 1" &>/dev/null; do
        retries=$((retries + 1))
        if [ $retries -gt 30 ]; then
            print_warning "Timeout aguardando catalog database"
            break
        fi
        sleep 2
    done

    print_step "Criando tabelas principais (Games, MassTransit Outbox)..."
    kubectl exec deployment/postgres -n "$NAMESPACE" -- psql -U catalog -d fcg_catalog_db \
        -c "$(cat "$SCRIPT_DIR/init-catalog-tables.sql")" 2>/dev/null && \
        print_success "Tabelas principais criadas" || \
        print_warning "Tabelas principais podem já existir"

    print_step "Criando tabelas extras (Orders, LibraryItems)..."
    kubectl exec deployment/postgres -n "$NAMESPACE" -- psql -U catalog -d fcg_catalog_db \
        -c "$(cat "$SCRIPT_DIR/init-catalog-extra-tables.sql")" 2>/dev/null && \
        print_success "Tabelas extras criadas" || \
        print_warning "Tabelas extras podem já existir"

    # ─── 9. RabbitMQ Exchange Bindings ────────────────────────────
    print_header "9️⃣  Configurando RabbitMQ Exchange Bindings"
    print_step "Aguardando RabbitMQ management API..."
    retries=0
    while ! kubectl exec deployment/rabbitmq -n "$NAMESPACE" -- rabbitmqctl status &>/dev/null; do
        retries=$((retries + 1))
        if [ $retries -gt 30 ]; then
            print_warning "Timeout aguardando RabbitMQ"
            break
        fi
        sleep 2
    done
    # Esperar os microserviços criarem as exchanges
    print_step "Aguardando microserviços criarem exchanges (15s)..."
    sleep 15

    print_step "Criando bindings para o Orchestrator..."

    # Declarar exchanges que podem não existir ainda
    kubectl exec deployment/rabbitmq -n "$NAMESPACE" -- \
        rabbitmqadmin -u admin -p admin123 declare exchange \
        name="Contracts.IntegrationEvents:UserCreatedEventV1" type=fanout durable=true 2>/dev/null || true

    # UserCreated: fanout exchange → orchestrator queue + notification queue
    kubectl exec deployment/rabbitmq -n "$NAMESPACE" -- \
        rabbitmqadmin -u admin -p admin123 declare binding \
        source="Contracts.IntegrationEvents:UserCreatedEventV1" \
        destination="user-created" destination_type=queue 2>/dev/null && \
        print_success "Binding: UserCreatedEvent → user-created" || \
        print_warning "Binding UserCreatedEvent pode já existir"

    kubectl exec deployment/rabbitmq -n "$NAMESPACE" -- \
        rabbitmqadmin -u admin -p admin123 declare binding \
        source="Contracts.IntegrationEvents:UserCreatedEventV1" \
        destination="user-created-queue" destination_type=queue 2>/dev/null || true

    # OrderPlaced: topic exchange → orchestrator queue
    kubectl exec deployment/rabbitmq -n "$NAMESPACE" -- \
        rabbitmqadmin -u admin -p admin123 declare binding \
        source="fcg.catalog" destination="order-placed" \
        destination_type=queue routing_key="v1.order-placed" 2>/dev/null && \
        print_success "Binding: OrderPlaced → order-placed" || \
        print_warning "Binding OrderPlaced pode já existir"

    # PaymentProcessed: topic exchange → orchestrator queue + notification queue
    kubectl exec deployment/rabbitmq -n "$NAMESPACE" -- \
        rabbitmqadmin -u admin -p admin123 declare binding \
        source="fcg.payments" destination="payment-processed" \
        destination_type=queue routing_key="v1.payment-processed" 2>/dev/null && \
        print_success "Binding: PaymentProcessed → payment-processed" || \
        print_warning "Binding PaymentProcessed pode já existir"

    kubectl exec deployment/rabbitmq -n "$NAMESPACE" -- \
        rabbitmqadmin -u admin -p admin123 declare binding \
        source="fcg.payments" destination="payment-processed-queue" \
        destination_type=queue routing_key="v1.payment-processed" 2>/dev/null || true

    # ─── 10. Port-Forwards ────────────────────────────────────────
    print_header "🔟  Iniciando Port-Forwards"
    # Mata port-forwards anteriores
    pkill -f "kubectl port-forward.*fcg-tech-fase-2" 2>/dev/null || true
    sleep 1

    kubectl port-forward svc/users-api 8080:80 -n "$NAMESPACE" &>/dev/null &
    kubectl port-forward svc/payments-api 8081:80 -n "$NAMESPACE" &>/dev/null &
    kubectl port-forward svc/catalog-api 8082:80 -n "$NAMESPACE" &>/dev/null &
    kubectl port-forward svc/notification-api 8083:80 -n "$NAMESPACE" &>/dev/null &
    kubectl port-forward svc/rabbitmq 15672:15672 -n "$NAMESPACE" &>/dev/null &
    sleep 2
    print_success "Port-forwards ativos: 8080(users) 8081(payments) 8082(catalog) 8083(notification) 15672(rabbitmq)"

    # ─── 11. Status Final ─────────────────────────────────────────
    print_header "📊 Status Final do Deploy"
    echo ""
    kubectl get pods -n "$NAMESPACE"
    echo ""
    kubectl get svc -n "$NAMESPACE"
    
    echo ""
    print_header "🎉 Deploy Completo!"
    echo ""
    echo -e "${GREEN}Todos os serviços foram deployados com sucesso!${NC}"
    echo -e "${GREEN}Port-forwards já estão rodando em background.${NC}"
    echo ""
    echo -e "${YELLOW}Para testar o fluxo completo:${NC}"
    echo -e "  bash ${SCRIPT_DIR}/test-e2e.sh"
    echo ""
    echo -e "${YELLOW}Comandos úteis:${NC}"
    echo -e "  kubectl get pods -n $NAMESPACE"
    echo -e "  kubectl logs deployment/orchestrator -n $NAMESPACE --tail=20"
    echo -e "  bash ${SCRIPT_DIR}/deploy.sh --status"
    echo ""
}

# ─── Main ─────────────────────────────────────────────────────────

case "${1:-}" in
    --destroy)
        delete_all
        echo ""
        echo -e "${BLUE}Recriando do zero em 5 segundos...${NC}"
        sleep 5
        deploy_all
        ;;
    --delete)
        delete_all
        ;;
    --status)
        show_status
        ;;
    --help|-h)
        echo "Uso: $0 [opção]"
        echo ""
        echo "Opções:"
        echo "  (sem opção)   Deploy completo (cria o que falta)"
        echo "  --destroy     Remove tudo e recria do zero"
        echo "  --delete      Apenas remove tudo"
        echo "  --status      Mostra status atual"
        echo "  --help        Mostra esta ajuda"
        ;;
    *)
        deploy_all
        ;;
esac
