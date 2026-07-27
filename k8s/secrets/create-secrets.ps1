$ErrorActionPreference = "Stop"

$Namespace = "fcg-tech-fase-4"

$RequiredVariables = @(
    "POSTGRES_ADMIN_USERNAME",
    "POSTGRES_ADMIN_PASSWORD",
    "POSTGRES_USERS_USERNAME",
    "POSTGRES_USERS_PASSWORD",
    "POSTGRES_CATALOG_USERNAME",
    "POSTGRES_CATALOG_PASSWORD",
    "POSTGRES_PAYMENTS_USERNAME",
    "POSTGRES_PAYMENTS_PASSWORD",
    "MONGODB_ROOT_USERNAME",
    "MONGODB_ROOT_PASSWORD",
    "RABBITMQ_USERNAME",
    "RABBITMQ_PASSWORD",
    "REDIS_PASSWORD"
)

foreach ($variableName in $RequiredVariables) {
  $value = [Environment]::GetEnvironmentVariable($variableName)
  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Required environment variable '$variableName' is not set."
  }
}

Write-Host "Creating or updating secrets in namespace '$Namespace'..."

kubectl create secret generic postgres-secret `
  --namespace=$Namespace `
  --from-literal=username=$env:POSTGRES_ADMIN_USERNAME `
  --from-literal=password=$env:POSTGRES_ADMIN_PASSWORD `
  --from-literal=users-username=$env:POSTGRES_USERS_USERNAME `
  --from-literal=users-password=$env:POSTGRES_USERS_PASSWORD `
  --from-literal=catalog-username=$env:POSTGRES_CATALOG_USERNAME `
  --from-literal=catalog-password=$env:POSTGRES_CATALOG_PASSWORD `
  --from-literal=payments-username=$env:POSTGRES_PAYMENTS_USERNAME `
  --from-literal=payments-password=$env:POSTGRES_PAYMENTS_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic mongodb-secret `
  --namespace=$Namespace `
  --from-literal=username=$env:MONGODB_ROOT_USERNAME `
  --from-literal=password=$env:MONGODB_ROOT_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic rabbitmq-secret `
  --namespace=$Namespace `
  --from-literal=username=$env:RABBITMQ_USERNAME `
  --from-literal=password=$env:RABBITMQ_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic redis-secret `
  --namespace=$Namespace `
  --from-literal=password=$env:REDIS_PASSWORD `
  --dry-run=client -o yaml | kubectl apply -f -

Write-Host "Secrets created or updated successfully."
