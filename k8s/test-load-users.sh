#!/bin/bash
#═══════════════════════════════════════════════════════════════
# 📊 Teste de Carga - UsersAPI
# Gera tráfego diverso para popular dashboards no Grafana
# Registros, Logins, GETs (cache), 404s, 401s
#═══════════════════════════════════════════════════════════════

KONG_URL="http://localhost:80"
NS="fcg-tech-fase-2"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }
info() { echo -e "  ${CYAN}ℹ️  $1${NC}"; }
step() { echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${YELLOW}  $1${NC}"; echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }
summary_line() { printf "  ${BLUE}%-35s${NC} %s\n" "$1" "$2"; }

TOTAL_REQUESTS=0
TOTAL_SUCCESS=0
TOTAL_ERRORS=0
TIMESTAMP=$(date +%s)

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  📊 TESTE DE CARGA - USERS API (via Kong)"
echo "  Objetivo: Gerar métricas para Prometheus/Grafana"
echo "═══════════════════════════════════════════════════════════════"

# ─── Verificar Kong acessível ─────────────────────────────────
step "PASSO 0: 🔌 Verificar conectividade com Kong"
KONG_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "${KONG_URL}/" 2>/dev/null)
if [ "$KONG_STATUS" != "000" ]; then
  pass "Kong acessível em ${KONG_URL} (HTTP ${KONG_STATUS})"
else
  fail "Kong não acessível em ${KONG_URL}"
  info "Verifique se o port-forward está ativo: kubectl port-forward svc/kong-proxy 80:80 -n ${NS}"
  exit 1
fi

# ═══════════════════════════════════════════════════════════════
# PASSO 1: REGISTROS EM MASSA
# ═══════════════════════════════════════════════════════════════
step "PASSO 1: 👤 Registrar 20 usuários (POST /api/users/register)"
REG_OK=0
REG_FAIL=0
for i in $(seq 1 20); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KONG_URL}/api/users/register" \
    -H "Content-Type: application/json" \
    -d "{\"fullName\":\"LoadTest${TIMESTAMP} User${i}\",\"email\":\"lt${TIMESTAMP}_user${i}@test.com\",\"password\":\"Test@12345\",\"confirmPassword\":\"Test@12345\"}")
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
  if [ "$CODE" = "201" ] || [ "$CODE" = "200" ]; then
    REG_OK=$((REG_OK + 1))
    TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
  else
    REG_FAIL=$((REG_FAIL + 1))
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
  fi
done
pass "Registros: ${REG_OK} sucesso, ${REG_FAIL} falhas"

# ═══════════════════════════════════════════════════════════════
# PASSO 2: LOGINS EM MASSA (SUCESSO)
# ═══════════════════════════════════════════════════════════════
step "PASSO 2: 🔑 Login de 20 usuários (POST /api/users/login)"
LOGIN_OK=0
LOGIN_FAIL=0
TOKEN=""
for i in $(seq 1 20); do
  RESP=$(curl -s -w "\n%{http_code}" -X POST "${KONG_URL}/api/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"lt${TIMESTAMP}_user${i}@test.com\",\"password\":\"Test@12345\"}")
  CODE=$(echo "$RESP" | tail -1)
  BODY=$(echo "$RESP" | sed '$d')
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
  if [ "$CODE" = "200" ]; then
    LOGIN_OK=$((LOGIN_OK + 1))
    TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    # Guardar o último token válido
    TOKEN=$(echo "$BODY" | python3 -c "import sys,json; print(json.load(sys.stdin).get('token',''))" 2>/dev/null)
  else
    LOGIN_FAIL=$((LOGIN_FAIL + 1))
    TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
  fi
done
pass "Logins OK: ${LOGIN_OK}, Falhas: ${LOGIN_FAIL}"
if [ -n "$TOKEN" ]; then
  info "Token obtido: ${TOKEN:0:40}..."
else
  fail "Nenhum token obtido — abortando testes autenticados"
  exit 1
fi

# Obter um User ID para testes GET
USER_ID=$(echo "$BODY" | python3 -c "
import sys,json,base64
d=json.load(sys.stdin)
t=d.get('token','')
parts=t.split('.')
if len(parts)>=2:
    payload=parts[1]+'=='
    claims=json.loads(base64.urlsafe_b64decode(payload))
    for k in ['http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier','sub','id']:
        if k in claims:
            print(claims[k])
            break
" 2>/dev/null)
info "User ID: ${USER_ID:-desconhecido}"

# ═══════════════════════════════════════════════════════════════
# PASSO 3: LOGINS COM SENHA ERRADA (401)
# ═══════════════════════════════════════════════════════════════
step "PASSO 3: 🚫 Logins com senha errada — 15x (espera-se 401)"
ERR_401=0
for i in $(seq 1 15); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KONG_URL}/api/users/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"lt${TIMESTAMP}_user${i}@test.com\",\"password\":\"WrongPassword!\"}")
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
  if [ "$CODE" = "401" ]; then
    ERR_401=$((ERR_401 + 1))
  fi
  TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
done
pass "401 Unauthorized recebidos: ${ERR_401}/15"

# ═══════════════════════════════════════════════════════════════
# PASSO 4: GET USER - CACHE MISS + CACHE HITS
# ═══════════════════════════════════════════════════════════════
step "PASSO 4: 🔄 GET /api/users/{id} — 50x (1 cache miss + 49 cache hits)"
GET_OK=0
GET_FAIL=0
if [ -n "$USER_ID" ]; then
  for i in $(seq 1 50); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" "${KONG_URL}/api/users/${USER_ID}" \
      -H "Authorization: Bearer ${TOKEN}")
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    if [ "$CODE" = "200" ]; then
      GET_OK=$((GET_OK + 1))
      TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    else
      GET_FAIL=$((GET_FAIL + 1))
      TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
    fi
  done
  pass "GET OK: ${GET_OK}, Falhas: ${GET_FAIL}"
  info "Cache: 1 miss esperado + $((GET_OK - 1)) hits esperados"
else
  info "User ID não disponível — pulando"
fi

# ═══════════════════════════════════════════════════════════════
# PASSO 5: GET COM ID INVÁLIDO (404)
# ═══════════════════════════════════════════════════════════════
step "PASSO 5: 🔍 GET /api/users/{id_invalido} — 20x (espera-se 404)"
ERR_404=0
for i in $(seq 1 20); do
  FAKE_ID="00000000-0000-0000-0000-$(printf '%012d' $i)"
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "${KONG_URL}/api/users/${FAKE_ID}" \
    -H "Authorization: Bearer ${TOKEN}")
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
  if [ "$CODE" = "404" ]; then
    ERR_404=$((ERR_404 + 1))
  fi
  TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
done
pass "404 Not Found recebidos: ${ERR_404}/20"

# ═══════════════════════════════════════════════════════════════
# PASSO 6: REQUESTS SEM TOKEN (401 via Kong)
# ═══════════════════════════════════════════════════════════════
step "PASSO 6: 🔒 GET /api/users/{id} sem token — 10x (Kong retorna 401)"
KONG_401=0
for i in $(seq 1 10); do
  CODE=$(curl -s -o /dev/null -w "%{http_code}" "${KONG_URL}/api/users/${USER_ID:-00000000-0000-0000-0000-000000000001}")
  TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
  if [ "$CODE" = "401" ]; then
    KONG_401=$((KONG_401 + 1))
  fi
  TOTAL_ERRORS=$((TOTAL_ERRORS + 1))
done
pass "401 (Kong JWT) recebidos: ${KONG_401}/10"

# ═══════════════════════════════════════════════════════════════
# PASSO 7: TRÁFEGO MISTO EM ONDAS
# ═══════════════════════════════════════════════════════════════
step "PASSO 7: 🌊 Tráfego misto em 3 ondas (Register + Login + GET)"
for round in $(seq 1 3); do
  echo -e "  ${CYAN}--- Onda ${round}/3 ---${NC}"
  WAVE_OK=0

  # 5 registros
  for i in $(seq 1 5); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KONG_URL}/api/users/register" \
      -H "Content-Type: application/json" \
      -d "{\"fullName\":\"Wave${round}${TIMESTAMP} U${i}\",\"email\":\"w${round}${TIMESTAMP}u${i}@test.com\",\"password\":\"Test@12345\",\"confirmPassword\":\"Test@12345\"}")
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    [ "$CODE" = "201" ] || [ "$CODE" = "200" ] && WAVE_OK=$((WAVE_OK + 1)) && TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
  done

  # 5 logins
  for i in $(seq 1 5); do
    CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "${KONG_URL}/api/users/login" \
      -H "Content-Type: application/json" \
      -d "{\"email\":\"w${round}${TIMESTAMP}u${i}@test.com\",\"password\":\"Test@12345\"}")
    TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
    [ "$CODE" = "200" ] && WAVE_OK=$((WAVE_OK + 1)) && TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
  done

  # 15 GETs (cache hits)
  if [ -n "$USER_ID" ]; then
    for i in $(seq 1 15); do
      CODE=$(curl -s -o /dev/null -w "%{http_code}" "${KONG_URL}/api/users/${USER_ID}" \
        -H "Authorization: Bearer ${TOKEN}")
      TOTAL_REQUESTS=$((TOTAL_REQUESTS + 1))
      [ "$CODE" = "200" ] && WAVE_OK=$((WAVE_OK + 1)) && TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    done
  fi

  pass "Onda ${round}: ${WAVE_OK} requisições com sucesso"
  sleep 3  # Pausa para criar variação temporal no Grafana
done

# ═══════════════════════════════════════════════════════════════
# PASSO 8: VERIFICAR MÉTRICAS NO PROMETHEUS
# ═══════════════════════════════════════════════════════════════
step "PASSO 8: 📊 Verificar métricas no Prometheus"

info "Aguardando 15s para o Prometheus coletar as métricas..."
sleep 15

# Buscar métricas via pod temporário
METRICS=$(kubectl run test-metrics-load --image=busybox:1.36 --rm -it --restart=Never -n ${NS} -- \
  sh -c 'wget -qO- http://users-api:80/metrics 2>/dev/null' 2>/dev/null)

# Extrair valores
HTTP_TOTAL=$(echo "$METRICS" | grep 'http_requests_received_total' | grep -v '#' | awk '{sum+=$2} END {printf "%d", sum}')
CACHE_HITS=$(echo "$METRICS" | grep 'cache_hits_total' | grep -v '#' | awk '{sum+=$2} END {printf "%d", sum}')
CACHE_MISSES=$(echo "$METRICS" | grep 'cache_misses_total' | grep -v '#' | awk '{sum+=$2} END {printf "%d", sum}')
USERS_REG=$(echo "$METRICS" | grep 'users_registered_total' | grep -v '#' | awk '{sum+=$2} END {printf "%d", sum}')

if [ "$HTTP_TOTAL" -gt 0 ] 2>/dev/null; then
  pass "Métricas encontradas no Prometheus!"
else
  fail "Métricas não encontradas — verifique se prometheus-net está configurado"
fi

# ═══════════════════════════════════════════════════════════════
# PASSO 9: VERIFICAR CACHE NO REDIS
# ═══════════════════════════════════════════════════════════════
step "PASSO 9: 🗄️  Verificar chaves no Redis"
REDIS_KEYS=$(kubectl exec deployment/redis -n ${NS} -- sh -c 'redis-cli -a "$REDIS_PASSWORD" KEYS "users:*" 2>/dev/null' 2>/dev/null)
REDIS_COUNT=$(echo "$REDIS_KEYS" | grep -c "users:" 2>/dev/null || echo "0")

if [ "$REDIS_COUNT" -gt 0 ]; then
  pass "Redis contém ${REDIS_COUNT} chave(s) com prefixo 'users:'"
  echo "$REDIS_KEYS" | head -5 | while read -r key; do
    info "  $key"
  done
else
  fail "Nenhuma chave 'users:*' encontrada no Redis"
fi

# ═══════════════════════════════════════════════════════════════
# RESUMO FINAL
# ═══════════════════════════════════════════════════════════════
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  📊 RESUMO DO TESTE DE CARGA"
echo "═══════════════════════════════════════════════════════════════"
echo ""
summary_line "Total de requisições:" "${TOTAL_REQUESTS}"
summary_line "Sucesso (2xx):" "${TOTAL_SUCCESS}"
summary_line "Erros (4xx/5xx):" "${TOTAL_ERRORS}"
echo ""
echo -e "  ${BLUE}── Métricas do Prometheus ──${NC}"
summary_line "http_requests_received_total:" "${HTTP_TOTAL:-N/A}"
summary_line "cache_hits_total:" "${CACHE_HITS:-N/A}"
summary_line "cache_misses_total:" "${CACHE_MISSES:-N/A}"
summary_line "users_registered_total:" "${USERS_REG:-N/A}"
echo ""
if [ "$CACHE_HITS" -gt 0 ] && [ "$CACHE_MISSES" -gt 0 ] 2>/dev/null; then
  HIT_RATE=$((CACHE_HITS * 100 / (CACHE_HITS + CACHE_MISSES)))
  summary_line "Cache Hit Rate:" "${HIT_RATE}%"
fi
summary_line "Chaves no Redis:" "${REDIS_COUNT}"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo -e "  ${GREEN}✅ Teste finalizado! Verifique o dashboard no Grafana:${NC}"
echo -e "  ${CYAN}   http://localhost:3000${NC}"
echo "═══════════════════════════════════════════════════════════════"
echo ""
