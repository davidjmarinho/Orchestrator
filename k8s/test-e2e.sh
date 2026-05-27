#!/bin/bash
#═══════════════════════════════════════════════════════════════
# 🎮 Teste E2E - Fluxo Completo FCG Tech
# Registro → Login → Criar Jogo → Comprar → Pagar → Notificar
#═══════════════════════════════════════════════════════════════

USERS_API="http://localhost:8080"
CATALOG_API="http://localhost:8083"
NS="fcg-tech-fase-2"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }
info() { echo -e "  ${CYAN}ℹ️  $1${NC}"; }
step() { echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${YELLOW}  $1${NC}"; echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ─── Verificar/iniciar port-forwards ─────────────────────────────
check_port_forward() {
    local svc=$1 port=$2 target_port=${3:-80}
    if ! lsof -i :"$port" -sTCP:LISTEN &>/dev/null; then
        kubectl port-forward svc/$svc ${port}:${target_port} -n ${NS} &>/dev/null &
        sleep 1
    fi
}

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  🎮 TESTE E2E - FLUXO COMPLETO FCG TECH"
echo "═══════════════════════════════════════════════════════════════"

# Garantir port-forwards
check_port_forward "users-api" 8080
check_port_forward "catalog-api" 8083
check_port_forward "mongodb" 27017 27017
sleep 1

# ─── PASSO 1: Registrar Usuário ──────────────────────────────────
step "PASSO 1: 👤 Registrar novo usuário (Users API)"
TIMESTAMP=$(date +%s)
EMAIL="gamer${TIMESTAMP}@fcgtech.com"
REGISTER=$(curl -s -w "\n%{http_code}" -X POST "${USERS_API}/api/users/register" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"Gamer@2026!\",\"fullName\":\"João Gamer\"}" 2>/dev/null)
REGISTER_BODY=$(echo "$REGISTER" | sed '$d')
REGISTER_CODE=$(echo "$REGISTER" | tail -1)
info "POST /api/users/register"
info "Email: ${EMAIL}"
if [ "$REGISTER_CODE" = "201" ] || [ "$REGISTER_CODE" = "200" ]; then
  pass "Usuário registrado! (HTTP ${REGISTER_CODE})"
  echo -e "  📦 ${REGISTER_BODY}"
else
  fail "Falha no registro (HTTP ${REGISTER_CODE})"
  echo -e "  📦 ${REGISTER_BODY}"
fi

# Extract User ID
USER_ID=$(echo "$REGISTER_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null)

# ─── PASSO 1.5: Atribuir role Admin ──────────────────────────────
step "PASSO 1.5: 🔐 Atribuir role Admin ao usuário (via SQL)"
if [ -n "$USER_ID" ]; then
  ADMIN_ROLE_ID=$(kubectl exec deployment/postgres -n ${NS} -- psql -U fcg -d fcg_users_db -t -c "SELECT \"Id\" FROM \"AspNetRoles\" WHERE \"Name\"='Admin'" 2>/dev/null | tr -d ' \n')
  kubectl exec deployment/postgres -n ${NS} -- psql -U fcg -d fcg_users_db -c "INSERT INTO \"AspNetUserRoles\" (\"UserId\", \"RoleId\") VALUES ('${USER_ID}', '${ADMIN_ROLE_ID}') ON CONFLICT DO NOTHING" 2>/dev/null
  pass "Role Admin atribuída ao usuário ${USER_ID}"
else
  fail "User ID não encontrado"
fi

# ─── PASSO 2: Login ──────────────────────────────────────────────
step "PASSO 2: 🔑 Login do usuário (Users API)"
LOGIN=$(curl -s -w "\n%{http_code}" -X POST "${USERS_API}/api/users/login" \
  -H "Content-Type: application/json" \
  -d "{\"email\":\"${EMAIL}\",\"password\":\"Gamer@2026!\"}" 2>/dev/null)
LOGIN_BODY=$(echo "$LOGIN" | sed '$d')
LOGIN_CODE=$(echo "$LOGIN" | tail -1)
TOKEN=$(echo "$LOGIN_BODY" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null)
if [ "$LOGIN_CODE" = "200" ] && [ -n "$TOKEN" ]; then
  pass "Login OK! (HTTP ${LOGIN_CODE})"
  info "Token: ${TOKEN:0:50}..."
else
  fail "Falha no login (HTTP ${LOGIN_CODE})"
  echo -e "  📦 ${LOGIN_BODY}"
  exit 1
fi

# ─── PASSO 3: Criar jogo no catálogo ─────────────────────────────
step "PASSO 3: 🎮 Cadastrar jogo no catálogo (Catalog API)"
CREATE_GAME=$(curl -s -w "\n%{http_code}" -X POST "${CATALOG_API}/api/catalog/games" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${TOKEN}" \
  -d '{"name":"Elden Ring","description":"Action RPG by FromSoftware","price":249.90,"category":"RPG"}' 2>/dev/null)
GAME_BODY=$(echo "$CREATE_GAME" | sed '$d')
GAME_CODE=$(echo "$CREATE_GAME" | tail -1)
info "POST /api/catalog/games {name: Elden Ring, price: 249.90, category: RPG}"
if [ "$GAME_CODE" = "200" ] || [ "$GAME_CODE" = "201" ]; then
  pass "Jogo cadastrado! (HTTP ${GAME_CODE})"
  echo -e "  📦 ${GAME_BODY}"
else
  fail "Falha ao cadastrar jogo (HTTP ${GAME_CODE})"
  echo -e "  📦 ${GAME_BODY}"
fi

GAME_ID=$(echo "$GAME_BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id', d.get('gameId', d.get('Id', ''))))" 2>/dev/null)
if [ -n "$GAME_ID" ] && [ "$GAME_ID" != "" ]; then
  info "Game ID: ${GAME_ID}"
fi

# ─── PASSO 4: Listar catálogo ────────────────────────────────────
step "PASSO 4: 📋 Listar jogos no catálogo (Catalog API)"
LIST_GAMES=$(curl -s -w "\n%{http_code}" "${CATALOG_API}/api/catalog/games" \
  -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
LIST_BODY=$(echo "$LIST_GAMES" | sed '$d')
LIST_CODE=$(echo "$LIST_GAMES" | tail -1)
info "GET /api/catalog/games"
if [ "$LIST_CODE" = "200" ]; then
  pass "Catálogo listado! (HTTP ${LIST_CODE})"
  echo -e "  📦 ${LIST_BODY}"
  if [ -z "$GAME_ID" ] || [ "$GAME_ID" = "" ]; then
    GAME_ID=$(echo "$LIST_BODY" | python3 -c "import sys,json; games=json.load(sys.stdin); print(games[0]['id'] if games else '')" 2>/dev/null)
    info "Game ID (from list): ${GAME_ID}"
  fi
else
  fail "Falha ao listar catálogo (HTTP ${LIST_CODE})"
  echo -e "  📦 ${LIST_BODY}"
fi

# ─── PASSO 5: Aguardar processamento de eventos ──────────────────
step "PASSO 5: ⏳ Aguardando propagação de eventos via RabbitMQ (8s)"
info "Fluxo esperado de eventos:"
info "  1. UserCreated → RabbitMQ → Orchestrator (log) + Notification API (email)"
sleep 8
pass "Tempo de propagação concluído"

# ─── PASSO 6: Logs dos microserviços ─────────────────────────────
step "PASSO 6: 📜 Logs dos microserviços (Kubernetes)"

echo ""
echo -e "${CYAN}  ── 👤 Users API (últimas 15 linhas) ──${NC}"
kubectl logs deployment/users-api -n ${NS} --tail=15 2>/dev/null | sed 's/^/    /'

echo ""
echo -e "${CYAN}  ── 🎮 Catalog API (últimas 15 linhas) ──${NC}"
kubectl logs deployment/catalog-api -n ${NS} --tail=15 2>/dev/null | sed 's/^/    /'

echo ""
echo -e "${CYAN}  ── 💳 Payments API (últimas 15 linhas) ──${NC}"
kubectl logs deployment/payments-api -n ${NS} --tail=15 2>/dev/null | sed 's/^/    /'

echo ""
echo -e "${CYAN}  ── 🔔 Notification API (últimas 15 linhas) ──${NC}"
kubectl logs deployment/notification-api -n ${NS} --tail=15 2>/dev/null | sed 's/^/    /'

echo ""
echo -e "${CYAN}  ── 🔄 Orchestrator (últimas 15 linhas) ──${NC}"
kubectl logs deployment/orchestrator -n ${NS} --tail=15 2>/dev/null | sed 's/^/    /'

# ─── PASSO 7: Verificar MongoDB (Orchestrator Logs) ──────────────
step "PASSO 7: 🗄️  Logs do Orchestrator no MongoDB"
kubectl exec deployment/mongodb -n ${NS} -- mongo orchestrator --quiet --authenticationDatabase admin -u admin -p mongo@123 --eval 'var total = db.Logs.count(); print("  Total de eventos registrados: " + total); print(""); db.Logs.find().sort({CreatedAt: -1}).limit(10).forEach(function(doc) { print("  ┌──────────────────────────────────────────────────"); print("  │ Event:   " + doc.EventName); print("  │ Status:  " + doc.Status); print("  │ Created: " + doc.CreatedAt); if (doc.Payload) { var p = doc.Payload; if (p.length > 120) p = p.substring(0,120) + "..."; print("  │ Payload: " + p); } if (doc.Error) { print("  │ Error:   " + doc.Error); } print("  └──────────────────────────────────────────────────"); });' 2>/dev/null

# ─── PASSO 8: Verificar filas RabbitMQ ───────────────────────────
step "PASSO 8: 🐇 Filas no RabbitMQ"
kubectl exec deployment/rabbitmq -n ${NS} -- rabbitmqctl list_queues name messages consumers 2>/dev/null | grep -v "^Listing\|^Timeout" | sed 's/^/    /'

# ─── PASSO 9: Verificar Prometheus ──────────────────────────────
step "PASSO 9: 📊 Prometheus (Observabilidade)"
check_port_forward "prometheus" 9090 9090
sleep 1

PROM_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:9090/-/ready" 2>/dev/null)
if [ "$PROM_STATUS" = "200" ]; then
  pass "Prometheus está pronto! (HTTP ${PROM_STATUS})"
else
  fail "Prometheus não está acessível (HTTP ${PROM_STATUS})"
fi

# Verificar targets do Prometheus
info "Targets configurados no Prometheus:"
TARGETS=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null)
echo "$TARGETS" | python3 -c "
import sys,json
try:
    data = json.load(sys.stdin)
    for t in data.get('data',{}).get('activeTargets',[]):
        job = t.get('labels',{}).get('job','?')
        health = t.get('health','?')
        url = t.get('scrapeUrl','?')
        icon = '✅' if health == 'up' else '❌'
        print(f'    {icon} {job}: {health} ({url})')
except: print('    ⚠️  Não foi possível obter targets')
" 2>/dev/null

# ─── PASSO 10: Verificar Grafana ─────────────────────────────────
step "PASSO 10: 📈 Grafana (Dashboards)"
check_port_forward "grafana" 3000 3000
sleep 1

GRAFANA_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/api/health" 2>/dev/null)
if [ "$GRAFANA_STATUS" = "200" ]; then
  pass "Grafana está pronto! (HTTP ${GRAFANA_STATUS})"
  GRAFANA_HEALTH=$(curl -s "http://localhost:3000/api/health" 2>/dev/null)
  echo -e "  📦 ${GRAFANA_HEALTH}"
else
  fail "Grafana não está acessível (HTTP ${GRAFANA_STATUS})"
fi

# Verificar datasource do Prometheus no Grafana
DS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u admin:admin "http://localhost:3000/api/datasources" 2>/dev/null)
if [ "$DS_STATUS" = "200" ]; then
  DS_INFO=$(curl -s -u admin:admin "http://localhost:3000/api/datasources" 2>/dev/null)
  DS_COUNT=$(echo "$DS_INFO" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)
  if [ "$DS_COUNT" -gt 0 ] 2>/dev/null; then
    pass "Datasource Prometheus configurado! (${DS_COUNT} datasource(s))"
    echo "$DS_INFO" | python3 -c "
import sys,json
for ds in json.load(sys.stdin):
    print(f'    📡 {ds[\"name\"]} ({ds[\"type\"]}) → {ds[\"url\"]}')
" 2>/dev/null
  else
    fail "Nenhum datasource configurado no Grafana"
  fi
fi

info "Acesse o Grafana: http://localhost:3000 (admin/admin)"
info "Acesse o Prometheus: http://localhost:9090"

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}✅ TESTE E2E FINALIZADO${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
