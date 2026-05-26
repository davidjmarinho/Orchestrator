#!/bin/bash
# ============================================================
#  Kong Setup via Admin API
#  Recria serviços, rotas, plugins JWT e consumer
#  Pré-requisito: kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2
# ============================================================

KONG_ADMIN="http://localhost:8001"

echo "=========================================="
echo "  CONFIGURANDO KONG VIA ADMIN API"
echo "=========================================="
echo ""

# ── Verificar conectividade ─────────────────────────────────
echo "🔍 Verificando Kong Admin API..."
if ! curl -sf "$KONG_ADMIN/status" > /dev/null; then
  echo "❌ Kong Admin API não acessível em $KONG_ADMIN"
  echo "   Execute primeiro: kubectl port-forward svc/kong-admin 8001:8001 -n fcg-tech-fase-2"
  exit 1
fi
echo "✅ Kong Admin API acessível"
echo ""

# ── Plugin Global: CORS ────────────────────────────────────
echo "🌐 [1/7] Configurando plugin global CORS..."
curl -sf -X POST "$KONG_ADMIN/plugins" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "cors",
    "config": {
      "origins": ["*"],
      "methods": ["GET","POST","PUT","DELETE","PATCH","OPTIONS"],
      "headers": ["Authorization","Content-Type"],
      "max_age": 3600
    }
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('  id:', d.get('id','?'))" 2>/dev/null || \
  echo "  (CORS já configurado ou erro — verifique: GET $KONG_ADMIN/plugins)"
echo "✅ CORS configurado"
echo ""

# ── Serviço: Users API ─────────────────────────────────────
echo "👤 [2/7] Criando serviço users-api..."
curl -sf -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{"name":"users-api","url":"http://users-api:80"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('  id:', d.get('id','?'))" 2>/dev/null || \
  echo "  (Serviço já existe)"
echo "✅ Serviço users-api criado"
echo ""

# ── Rota Pública: login e registro (sem JWT) ───────────────
echo "🔓 [3/7] Criando rota pública users (login/register)..."
curl -sf -X POST "$KONG_ADMIN/services/users-api/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "users-api-public-route",
    "paths": ["~/api/users/login$","~/api/users/register$"],
    "methods": ["GET","POST","OPTIONS"],
    "strip_path": false
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('  id:', d.get('id','?'))" 2>/dev/null || \
  echo "  (Rota já existe)"
echo "✅ Rota pública criada"
echo ""

# ── Rota Protegida: demais endpoints de usuários (com JWT) ─
echo "🔒 [4/7] Criando rota protegida users (JWT obrigatório)..."
ROUTE_USERS_ID=$(curl -sf -X POST "$KONG_ADMIN/services/users-api/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "users-api-protected-route",
    "paths": ["/api/users"],
    "strip_path": false
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)

if [ -n "$ROUTE_USERS_ID" ]; then
  echo "  id: $ROUTE_USERS_ID"
  # Adicionar plugin JWT nesta rota
  curl -sf -X POST "$KONG_ADMIN/routes/$ROUTE_USERS_ID/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"jwt"}' > /dev/null
  echo "  Plugin JWT adicionado à rota"
else
  echo "  (Rota já existe — verificando plugin JWT...)"
  EXISTING_ROUTE=$(curl -sf "$KONG_ADMIN/services/users-api/routes/users-api-protected-route" | \
    python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)
  if [ -n "$EXISTING_ROUTE" ]; then
    curl -sf -X POST "$KONG_ADMIN/routes/$EXISTING_ROUTE/plugins" \
      -H "Content-Type: application/json" \
      -d '{"name":"jwt"}' > /dev/null 2>&1 || true
  fi
fi
echo "✅ Rota protegida users criada"
echo ""

# ── Serviço: Catalog API ───────────────────────────────────
echo "📦 [5/7] Criando serviço catalog-api..."
curl -sf -X POST "$KONG_ADMIN/services" \
  -H "Content-Type: application/json" \
  -d '{"name":"catalog-api","url":"http://catalog-api:80"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('  id:', d.get('id','?'))" 2>/dev/null || \
  echo "  (Serviço já existe)"

# Rota catalog-api com JWT
ROUTE_CATALOG_ID=$(curl -sf -X POST "$KONG_ADMIN/services/catalog-api/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "catalog-api-route",
    "paths": ["/api/catalog","/api/products"],
    "strip_path": false
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)

if [ -n "$ROUTE_CATALOG_ID" ]; then
  curl -sf -X POST "$KONG_ADMIN/routes/$ROUTE_CATALOG_ID/plugins" \
    -H "Content-Type: application/json" \
    -d '{"name":"jwt"}' > /dev/null
  echo "  Plugin JWT adicionado à rota catalog"
else
  echo "  (Rota já existe)"
fi
echo "✅ Serviço e rota catalog-api criados"
echo ""

# ── Consumer ───────────────────────────────────────────────
echo "🧑 [6/7] Criando consumer app-consumer..."
curl -sf -X POST "$KONG_ADMIN/consumers" \
  -H "Content-Type: application/json" \
  -d '{"username":"app-consumer"}' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print('  id:', d.get('id','?'))" 2>/dev/null || \
  echo "  (Consumer já existe)"
echo "✅ Consumer criado"
echo ""

# ── JWT Credential ─────────────────────────────────────────
echo "🔑 [7/7] Configurando credencial JWT..."
# algorithm: HS256 | key = claim "iss" do token | secret = chave de assinatura
curl -sf -X POST "$KONG_ADMIN/consumers/app-consumer/jwt" \
  -H "Content-Type: application/json" \
  -d '{
    "algorithm": "HS256",
    "key": "UsersAPI",
    "secret": "ChaveSuperSecretaCom32Caracteres!"
  }' | python3 -c "import sys,json; d=json.load(sys.stdin); print('  key:', d.get('key','?'))" 2>/dev/null || \
  echo "  (Credencial já existe)"
echo "✅ Credencial JWT configurada"
echo ""

echo "=========================================="
echo "  ✅ KONG CONFIGURADO COM SUCESSO!"
echo "=========================================="
echo ""
echo "📋 Resumo das rotas:"
echo "  Pública  → GET/POST /api/users/login"
echo "  Pública  → GET/POST /api/users/register"
echo "  JWT      → /api/users/*"
echo "  JWT      → /api/catalog/*"
echo "  JWT      → /api/products/*"
echo ""
echo "🔑 JWT esperado:"
echo "  Header:  Authorization: Bearer <token>"
echo "  Claim:   iss = UsersAPI"
echo "  Secret:  ChaveSuperSecretaCom32Caracteres!"
echo ""
echo "📊 Verificar configuração:"
echo "  curl $KONG_ADMIN/services"
echo "  curl $KONG_ADMIN/routes"
echo "  curl $KONG_ADMIN/plugins"
echo "  curl $KONG_ADMIN/consumers/app-consumer/jwt"
