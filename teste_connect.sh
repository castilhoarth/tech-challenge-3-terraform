#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== 1. Extraindo Endpoints e Credenciais da AWS ===${NC}"

# Busca os endpoints das instâncias RDS ativas
RDS_AUTH_HOST=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'auth')].Endpoint.Address" --output text)
RDS_FLAG_HOST=$(aws rds describe-db-instances --query "DBInstances[?contains(DBInstanceIdentifier, 'flag')].Endpoint.Address" --output text)

# Busca os nomes dos Secrets no AWS Secrets Manager
SECRET_AUTH_NAME=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'rds-auth')].Name" --output text | head -n 1)
SECRET_FLAG_NAME=$(aws secretsmanager list-secrets --query "SecretList[?contains(Name, 'rds-flag')].Name" --output text | head -n 1)

# Extrai as senhas do Secrets Manager
RDS_AUTH_PWD=$(aws secretsmanager get-secret-value --secret-id "$SECRET_AUTH_NAME" --query SecretString --output text | jq -r '.password // .')
RDS_FLAG_PWD=$(aws secretsmanager get-secret-value --secret-id "$SECRET_FLAG_NAME" --query SecretString --output text | jq -r '.password // .')

echo -e "Host Auth: ${GREEN}${RDS_AUTH_HOST}${NC}"
echo -e "Host Flag: ${GREEN}${RDS_FLAG_HOST}${NC}\n"

echo -e "${YELLOW}=== 2. Atualizando Kubeconfig do EKS ===${NC}"
aws eks update-kubeconfig --region us-east-1 --name togglemaster-eks

echo -e "\n${YELLOW}=== 3. Executando Testes de Conexão no Cluster EKS ===${NC}"

# Pod 1: Validar auth_db
echo -e "${YELLOW}[TESTE 1/3] Validando acesso ao auth_db...${NC}"
kubectl run db-test-auth --rm -i --tty --restart=Never --image=postgres:15-alpine \
  --env="PGPASSWORD=$RDS_AUTH_PWD" -- \
  psql -h $RDS_AUTH_HOST -U auth_user -d auth_db -c "SELECT current_database(), current_user, clock_timestamp();"

# Pod 2: Validar flag_db
echo -e "\n${YELLOW}[TESTE 2/3] Validando acesso ao flag_db...${NC}"
kubectl run db-test-flag --rm -i --tty --restart=Never --image=postgres:15-alpine \
  --env="PGPASSWORD=$RDS_FLAG_PWD" -- \
  psql -h $RDS_FLAG_HOST -U flag_user -d flag_db -c "SELECT current_database(), current_user, clock_timestamp();"

# Pod 3: Validar targeting_db
#echo -e "\n${YELLOW}[TESTE 3/3] Validando acesso ao targeting_db...${NC}"
#kubectl run db-test-targeting --rm -i --tty --restart=Never --image=postgres:15-alpine \
#  --env="PGPASSWORD=$RDS_FLAG_PWD" -- \
#  psql -h $RDS_FLAG_HOST -U flag_user -d targeting_db -c "SELECT current_database(), current_user, clock_timestamp();"

echo -e "\n${GREEN}=== Todos os testes de conectividade foram concluídos com sucesso! ===${NC}"