#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# init-aws.sh — Executado pelo LocalStack quando está pronto (ready.d)
# Cria todos os recursos AWS simulados para a NotificationsAPI Lambda.
#
# Para trocar de LocalStack para AWS real:
#   - Remova este script do workflow
#   - Execute os comandos abaixo apontando para AWS (sem --endpoint-url)
#   - Ou use Terraform/CDK com as mesmas definições de recursos
# ──────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REGION="us-east-1"
ACCOUNT_ID="000000000000"
IMAGE_NAME="${LAMBDA_IMAGE_NAME:-davidjmarinho/notifications-lambda:latest}"

echo "════════════════════════════════════════════════════"
echo "🚀 Inicializando recursos AWS no LocalStack"
echo "   Region:  $REGION"
echo "   Lambda:  $IMAGE_NAME"
echo "════════════════════════════════════════════════════"

# ── 1. Filas SQS ──────────────────────────────────────────────────────────────
echo ""
echo "📬 [1/4] Criando filas SQS..."

awslocal sqs create-queue \
  --queue-name "user-created-queue" \
  --attributes '{"VisibilityTimeout":"30","MessageRetentionPeriod":"86400"}' \
  --region "$REGION"

awslocal sqs create-queue \
  --queue-name "payment-processed-queue" \
  --attributes '{"VisibilityTimeout":"30","MessageRetentionPeriod":"86400"}' \
  --region "$REGION"

echo "✅ Filas criadas"

# ── 2. Role IAM (fictícia no LocalStack) ─────────────────────────────────────
echo ""
echo "🔑 [2/4] Criando role IAM..."

awslocal iam create-role \
  --role-name "lambda-notifications-role" \
  --assume-role-policy-document '{
    "Version":"2012-10-17",
    "Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]
  }' 2>/dev/null || echo "   (role já existe — OK)"

# ── 3. Lambda Function (Docker image) ─────────────────────────────────────────
echo ""
echo "⚡ [3/4] Criando Lambda Function..."

# Remove função anterior se existir
awslocal lambda delete-function \
  --function-name "notifications-lambda" \
  --region "$REGION" 2>/dev/null || true

awslocal lambda create-function \
  --function-name   "notifications-lambda" \
  --package-type    Image \
  --code            ImageUri="$IMAGE_NAME" \
  --role            "arn:aws:iam::${ACCOUNT_ID}:role/lambda-notifications-role" \
  --timeout         30 \
  --memory-size     256 \
  --environment     "Variables={MONGO_CONNECTION_STRING=mongodb://mongodb:27017,MONGO_DB=notifications,AWS_ENDPOINT_URL=http://localstack:4566,AWS_DEFAULT_REGION=us-east-1,AWS_ACCESS_KEY_ID=test,AWS_SECRET_ACCESS_KEY=test}" \
  --region "$REGION"

echo "⏳ Aguardando Lambda ficar Active..."
for i in $(seq 1 15); do
  STATE=$(awslocal lambda get-function \
    --function-name notifications-lambda \
    --region "$REGION" \
    --query 'Configuration.State' \
    --output text 2>/dev/null || echo "Pending")
  if [[ "$STATE" == "Active" ]]; then
    echo "✅ Lambda ativa!"
    break
  fi
  echo "   [$i/15] Estado: $STATE — aguardando 3s..."
  sleep 3
done

# ── 4. Event Source Mappings (SQS → Lambda) ───────────────────────────────────
echo ""
echo "🔗 [4/4] Criando Event Source Mappings (SQS → Lambda)..."

USER_QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT_ID}:user-created-queue"
PAYMENT_QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT_ID}:payment-processed-queue"

awslocal lambda create-event-source-mapping \
  --function-name  "notifications-lambda" \
  --event-source-arn "$USER_QUEUE_ARN" \
  --batch-size 1 \
  --region "$REGION" 2>/dev/null || echo "   (mapping user-created já existe)"

awslocal lambda create-event-source-mapping \
  --function-name  "notifications-lambda" \
  --event-source-arn "$PAYMENT_QUEUE_ARN" \
  --batch-size 1 \
  --region "$REGION" 2>/dev/null || echo "   (mapping payment-processed já existe)"

# ── Resumo ────────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════"
echo "✅ LocalStack inicializado com sucesso!"
echo ""
echo "   SQS:    user-created-queue"
echo "          payment-processed-queue"
echo "   Lambda: notifications-lambda ($IMAGE_NAME)"
echo "   Mongo:  mongodb://mongodb:27017/notifications"
echo ""
echo "Para AWS real, use os mesmos comandos sem --endpoint-url"
echo "e substitua credenciais por IAM Role."
echo "════════════════════════════════════════════════════"
