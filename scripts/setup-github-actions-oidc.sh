#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-github-actions-oidc.sh [owner/repo] [role-name]

Examples:
  ./scripts/setup-github-actions-oidc.sh owner/repo
  ./scripts/setup-github-actions-oidc.sh owner/repo GitHubActionsDeployRole
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REPO_SLUG="${1:-}"
ROLE_NAME="${2:-GitHubActionsDeployRole}"
AWS_REGION="${AWS_REGION:-us-east-1}"
OIDC_PROVIDER_URL="https://token.actions.githubusercontent.com"
OIDC_THUMBPRINT="${OIDC_THUMBPRINT:-}"

if [[ -z "$OIDC_THUMBPRINT" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    OIDC_THUMBPRINT="$(openssl s_client -connect token.actions.githubusercontent.com:443 -servername token.actions.githubusercontent.com </dev/null 2>/dev/null | openssl x509 -fingerprint -sha1 -noout | sed 's/^sha1 Fingerprint=//; s/://g' | tr '[:upper:]' '[:lower:]')"
  fi
fi

if [[ -z "$OIDC_THUMBPRINT" ]]; then
  echo "Unable to determine the GitHub OIDC thumbprint. Set OIDC_THUMBPRINT manually." >&2
  exit 1
fi

if [[ -z "$REPO_SLUG" ]]; then
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    REMOTE_URL="$(git config --get remote.origin.url || true)"
    if [[ "$REMOTE_URL" =~ github.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
      REPO_SLUG="${BASH_REMATCH[1]}"
    fi
  fi
fi

if [[ -z "$REPO_SLUG" ]]; then
  echo "Unable to infer GitHub repository. Pass owner/repo as the first argument." >&2
  exit 1
fi

OWNER="${REPO_SLUG%%/*}"
REPO="${REPO_SLUG#*/}"

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required but was not found in PATH." >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGION="${AWS_REGION}"

if [[ -z "$ACCOUNT_ID" || "$ACCOUNT_ID" == "None" ]]; then
  echo "Unable to resolve AWS account ID. Verify your AWS CLI credentials." >&2
  exit 1
fi

PROVIDER_ARN="$(aws iam list-open-id-connect-providers --query "OpenIDConnectProviderList[?Arn=='arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com'] | [0].Arn" --output text)"
if [[ -z "$PROVIDER_ARN" || "$PROVIDER_ARN" == "None" ]]; then
  echo "Creating GitHub OIDC provider..."
  aws iam create-open-id-connect-provider \
    --url "$OIDC_PROVIDER_URL" \
    --thumbprint-list "$OIDC_THUMBPRINT" \
    --client-id-list sts.amazonaws.com >/dev/null
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/trust-policy.json" <<EOF_TRUST
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:${REPO_SLUG}:ref:refs/heads/develop",
            "repo:${REPO_SLUG}:ref:refs/heads/main",
            "repo:${REPO_SLUG}:environment:develop",
            "repo:${REPO_SLUG}:environment:prod",
            "repo:${REPO_SLUG}:ref:refs/tags/v*"
          ]
        }
      }
    }
  ]
}
EOF_TRUST

cat > "$TMP_DIR/deploy-policy.json" <<'EOF_POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "EcrAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:GetAuthorizationToken",
        "ecr:InitiateLayerUpload",
        "ecr:PutImage",
        "ecr:UploadLayerPart"
      ],
      "Resource": "*"
    },
    {
      "Sid": "EksAccess",
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster"
      ],
      "Resource": "*"
    }
  ]
}
EOF_POLICY

ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text 2>/dev/null || true)"
if [[ -z "$ROLE_ARN" || "$ROLE_ARN" == "None" ]]; then
  echo "Creating IAM role ${ROLE_NAME}..."
  aws iam create-role \
    --role-name "$ROLE_NAME" \
    --assume-role-policy-document "file://$TMP_DIR/trust-policy.json" >/dev/null
  ROLE_ARN="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)"
else
  echo "Updating trust policy for existing role ${ROLE_NAME}..."
  aws iam update-assume-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-document "file://$TMP_DIR/trust-policy.json" >/dev/null
fi

aws iam put-role-policy \
  --role-name "$ROLE_NAME" \
  --policy-name GitHubActionsDeployPolicy \
  --policy-document "file://$TMP_DIR/deploy-policy.json" >/dev/null

cat <<EOF

GitHub Actions OIDC role created successfully.

Role ARN: ${ROLE_ARN}
Repository: ${REPO_SLUG}
Region: ${REGION}

Next steps:
1. Add this secret in GitHub: AWS_ROLE_TO_ASSUME=${ROLE_ARN}
2. Add this variable in GitHub: EKS_CLUSTER_NAME=<your-eks-cluster>
3. Add this variable in GitHub: K8S_NAMESPACE=<your-namespace>
4. Create the GitHub environment 'prod' and require approval.
5. Protect the 'develop' branch and require the CI status check.
EOF
