#!/bin/bash

set -u

REGION="us-east-1"
PROFILE="prod"
CLUSTER_NAME="togglemaster-eks"
TEST_POD="postgres-test"

PASS=0
FAIL=0

ok() {
    echo "  ✅ $1"
    PASS=$((PASS + 1))
}

fail() {
    echo "  ❌ $1"
    FAIL=$((FAIL + 1))
}

check() {
    local description="$1"
    shift

    if "$@" >/dev/null 2>&1; then
        ok "$description"
    else
        fail "$description"
    fi
}

echo "=========================================="
echo " ToggleMaster - Teste de Infraestrutura"
echo "=========================================="

# ==================================================
# 1. AWS
# ==================================================

echo
echo "[1] AWS"

if ACCOUNT_ID=$(aws sts get-caller-identity \
    --profile "$PROFILE" \
    --query Account \
    --output text 2>/dev/null); then

    ok "Credenciais AWS válidas"
    echo "      Account: $ACCOUNT_ID"
else
    fail "Credenciais AWS"
    echo
    echo "Não foi possível continuar sem acesso à AWS."
    exit 1
fi

# ==================================================
# 2. VPC
# ==================================================

echo
echo "[2] VPC"

VPC_ID=$(aws ec2 describe-vpcs \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=tech-challenge-vpc" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null)

if [ "$VPC_ID" != "None" ] && [ -n "$VPC_ID" ]; then
    ok "VPC encontrada: $VPC_ID"
else
    fail "VPC tech-challenge-vpc"
fi

PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=tag:kubernetes.io/role/elb,Values=1" \
    --query 'length(Subnets)' \
    --output text 2>/dev/null)

PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --profile "$PROFILE" \
    --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=tag:kubernetes.io/role/internal-elb,Values=1" \
    --query 'length(Subnets)' \
    --output text 2>/dev/null)

[ "$PUBLIC_SUBNETS" -ge 2 ] 2>/dev/null \
    && ok "Subnets públicas: $PUBLIC_SUBNETS" \
    || fail "Subnets públicas"

[ "$PRIVATE_SUBNETS" -ge 2 ] 2>/dev/null \
    && ok "Subnets privadas: $PRIVATE_SUBNETS" \
    || fail "Subnets privadas"

# ==================================================
# 3. EKS
# ==================================================

echo
echo "[3] EKS"

EKS_STATUS=$(aws eks describe-cluster \
    --name "$CLUSTER_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" \
    --query 'cluster.status' \
    --output text 2>/dev/null)

if [ "$EKS_STATUS" = "ACTIVE" ]; then
    ok "EKS cluster ACTIVE"
else
    fail "EKS cluster (status: $EKS_STATUS)"
fi

echo
echo "      Nodes:"

kubectl get nodes 2>/dev/null || true

READY_NODES=$(kubectl get nodes \
    --no-headers 2>/dev/null |
    grep -c ' Ready ' || true)

if [ "$READY_NODES" -gt 0 ]; then
    ok "Nodes Ready: $READY_NODES"
else
    fail "Nenhum node Ready"
fi

# ==================================================
# 4. EKS Add-ons
# ==================================================

echo
echo "[4] EKS Add-ons"

for addon in vpc-cni kube-proxy coredns; do

    STATUS=$(aws eks describe-addon \
        --cluster-name "$CLUSTER_NAME" \
        --addon-name "$addon" \
        --region "$REGION" \
        --profile "$PROFILE" \
        --query 'addon.status' \
        --output text 2>/dev/null || echo "NOT_FOUND")

    if [ "$STATUS" = "ACTIVE" ]; then
        ok "$addon: ACTIVE"
    else
        fail "$addon: $STATUS"
    fi

done

# ==================================================
# 5. RDS
# ==================================================

echo
echo "[5] RDS"

RDS_INSTANCES=$(aws rds describe-db-instances \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'DBInstances[].DBInstanceIdentifier' \
    --output text 2>/dev/null)

if [ -n "$RDS_INSTANCES" ]; then
    echo "$RDS_INSTANCES" | tr '\t' '\n' | while read -r db; do
        [ -n "$db" ] && echo "      $db"
    done

    RDS_COUNT=$(echo "$RDS_INSTANCES" | wc -w)

    if [ "$RDS_COUNT" -ge 2 ]; then
        ok "RDS encontrados: $RDS_COUNT"
    else
        fail "Esperados 2 RDS; encontrados: $RDS_COUNT"
    fi
else
    fail "Nenhum RDS encontrado"
fi

# ==================================================
# 6. Secrets Manager
# ==================================================

echo
echo "[6] Secrets Manager"

SECRET_NAMES=$(aws secretsmanager list-secrets \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'SecretList[].Name' \
    --output text 2>/dev/null)

echo "$SECRET_NAMES" | tr '\t' '\n' |
while read -r secret; do
    [ -n "$secret" ] && echo "      $secret"
done

AUTH_SECRET=$(echo "$SECRET_NAMES" |
    tr '\t' '\n' |
    grep -i 'auth' |
    head -1)

FLAG_SECRET=$(echo "$SECRET_NAMES" |
    tr '\t' '\n' |
    grep -i 'flag' |
    head -1)

[ -n "$AUTH_SECRET" ] \
    && ok "Secret do Auth encontrada" \
    || fail "Secret do Auth"

[ -n "$FLAG_SECRET" ] \
    && ok "Secret do Flag encontrada" \
    || fail "Secret do Flag"

# ==================================================
# 7. Redis
# ==================================================

echo
echo "[7] ElastiCache Redis"

REDIS_COUNT=$(aws elasticache describe-cache-clusters \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'length(CacheClusters)' \
    --output text 2>/dev/null || echo 0)

if [ "$REDIS_COUNT" -gt 0 ]; then
    ok "Redis encontrado"
else
    fail "Redis"
fi

# ==================================================
# 8. DynamoDB + SQS
# ==================================================

echo
echo "[8] DynamoDB / SQS"

TABLE_COUNT=$(aws dynamodb list-tables \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'length(TableNames)' \
    --output text 2>/dev/null || echo 0)

if [ "$TABLE_COUNT" -gt 0 ]; then
    ok "DynamoDB encontrado"
else
    fail "DynamoDB"
fi

QUEUE_COUNT=$(aws sqs list-queues \
    --profile "$PROFILE" \
    --region "$REGION" \
    --query 'length(QueueUrls)' \
    --output text 2>/dev/null || echo 0)

if [ "$QUEUE_COUNT" -gt 0 ]; then
    ok "SQS encontrado"
else
    fail "SQS"
fi

# ==================================================
# 9. ECR
# ==================================================

echo
echo "[9] ECR"

for repo in \
    auth-service \
    flag-service \
    targeting-service \
    evaluation-service \
    analytics-service
do

    if aws ecr describe-repositories \
        --repository-names "$repo" \
        --profile "$PROFILE" \
        --region "$REGION" \
        >/dev/null 2>&1; then

        ok "ECR: $repo"
    else
        fail "ECR: $repo"
    fi

done

# ==================================================
# 10. NGINX + Argo CD
# ==================================================

echo
echo "[10] NGINX / Argo CD"

# --------------------------------------------------
# NGINX
# --------------------------------------------------

echo
echo "      NGINX"

NGINX_STATUS=$(helm list \
    -n ingress-nginx \
    -o json 2>/dev/null |
    jq -r '.[] | select(.name=="ingress-nginx") | .status')

if [ "$NGINX_STATUS" = "deployed" ]; then
    ok "NGINX Helm release: deployed"
else
    fail "NGINX Helm release: $NGINX_STATUS"
fi

NGINX_READY=$(kubectl get deployment ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)

NGINX_DESIRED=$(kubectl get deployment ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)

if [ "$NGINX_READY" = "$NGINX_DESIRED" ] && [ "$NGINX_READY" -gt 0 ] 2>/dev/null; then
    ok "NGINX controller: $NGINX_READY/$NGINX_DESIRED Ready"
else
    fail "NGINX controller: $NGINX_READY/$NGINX_DESIRED Ready"
fi

NGINX_LB=$(kubectl get svc ingress-nginx-controller \
    -n ingress-nginx \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
    2>/dev/null)

if [ -n "$NGINX_LB" ]; then
    ok "NGINX LoadBalancer: $NGINX_LB"
else
    fail "NGINX LoadBalancer"
fi

# --------------------------------------------------
# Argo CD
# --------------------------------------------------

echo
echo "      Argo CD"

ARGO_STATUS=$(helm list \
    -n argocd \
    -o json 2>/dev/null |
    jq -r '.[] | select(.name=="argo-cd") | .status')

if [ "$ARGO_STATUS" = "deployed" ]; then
    ok "Argo CD Helm release: deployed"
else
    fail "Argo CD Helm release: $ARGO_STATUS"
fi

ARGO_PODS=$(kubectl get pods \
    -n argocd \
    --no-headers 2>/dev/null |
    wc -l)

ARGO_RUNNING=$(kubectl get pods \
    -n argocd \
    --no-headers 2>/dev/null |
    awk '$3=="Running" {count++} END {print count+0}')

if [ "$ARGO_PODS" -gt 0 ] && [ "$ARGO_RUNNING" -eq "$ARGO_PODS" ]; then
    ok "Argo CD Pods: $ARGO_RUNNING/$ARGO_PODS Running"
else
    fail "Argo CD Pods: $ARGO_RUNNING/$ARGO_PODS Running"
fi

ARGO_SERVICES=$(kubectl get svc \
    -n argocd \
    --no-headers 2>/dev/null |
    wc -l)

if [ "$ARGO_SERVICES" -gt 0 ]; then
    ok "Argo CD Services: $ARGO_SERVICES"
else
    fail "Argo CD Services"
fi

# ==================================================
# RESULTADO
# ==================================================

echo
echo "=========================================="
echo " RESULTADO"
echo "=========================================="

echo "  ✅ OK:      $PASS"
echo "  ❌ Falhas:  $FAIL"

echo

if [ "$FAIL" -eq 0 ]; then
    echo "🎉 INFRAESTRUTURA OK"
    exit 0
else
    echo "⚠️  EXISTEM PROBLEMAS NA INFRAESTRUTURA"
    exit 1
fi