# 🚀 ToggleMaster — Infrastructure as Code (IaC)

Este repositório contém a infraestrutura como código (IaC) automatizada para o **ToggleMaster**, uma plataforma de gerenciamento e avaliação de Feature Flags composta por **5 microsserviços**:

1. **Auth Service** — Autenticação e gestão de permissões.
2. **Flag Service** — Gerenciamento e cadastro de feature flags.
3. **Targeting Service** — Regras de direcionamento e segmentação de usuários.
4. **Evaluation Service** — Avaliação em tempo real de flags com baixa latência.
5. **Analytics Service** — Processamento e armazenamento de eventos de telemetria e auditoria.

A infraestrutura é provisionada utilizando **Terraform na AWS**, enquanto o deployment das aplicações Kubernetes é gerenciado através de **Argo CD**, seguindo uma abordagem GitOps.

---

## 🏗️ Arquitetura da Infraestrutura

```text
                                      +----------------------+
                                      |       GitHub         |
                                      | toggle-master-devops |
                                      +----------+-----------+
                                                 |
                                                 | GitOps
                                                 v
                                      +----------------------+
                                      |       Argo CD        |
                                      |    namespace argocd  |
                                      +----------+-----------+
                                                 |
                                                 | Sync
                                                 v
+--------------------------------------------------------------------------------+
|                                  AWS VPC                                      |
|                                                                                |
|   +------------------------------------------------------------------------+   |
|   |                              EKS Cluster                               |   |
|   |                                                                        |   |
|   |   +------------+  +------------+  +-------------+                     |   |
|   |   |    Auth    |  |    Flag    |  |  Targeting  |                     |   |
|   |   |  Service   |  |  Service   |  |   Service   |                     |   |
|   |   +------------+  +------------+  +-------------+                     |   |
|   |                                                                        |   |
|   |   +-------------+  +---------------+                                   |   |
|   |   | Evaluation  |  |   Analytics   |                                   |   |
|   |   |   Service   |  |    Service    |                                   |   |
|   |   +------+------+  +-------+-------+                                   |   |
|   |          |                 |                                           |   |
|   +----------|-----------------|-------------------------------------------+   |
|              |                 |                                               |
|              v                 v                                               |
|       +-------------+     +----------+                                         |
|       | ElastiCache |     |   SQS    |                                         |
|       |    Redis    |     |  Queue   |                                         |
|       +-------------+     +----+-----+                                         |
|                                |                                               |
|                                v                                               |
|                         +-------------+                                        |
|                         |  DynamoDB   |                                        |
|                         |  Analytics  |                                        |
|                         +-------------+                                        |
|                                                                                |
|   +-------------------+       +-------------------------------------------+   |
|   |    RDS Auth       |       |             RDS Flag                      |   |
|   |                   |       |                                           |   |
|   |    auth_db        |       |    flag_db       targeting_db             |   |
|   +-------------------+       +-------------------------------------------+   |
|                                                                                |
+--------------------------------------------------------------------------------+

                         AWS Secrets Manager
                                  |
                    +-------------+-------------+
                    |             |             |
              auth-master-key   rds-auth     rds-flag
                    |             |             |
                    +-------------+-------------+
                                  |
                                  v
                       External Secrets Operator
                                  |
                                  v
                         Kubernetes Secrets
```

---

# ☁️ AWS Infrastructure

A infraestrutura é composta pelos seguintes componentes:

### Networking

- VPC dedicada.
- Subnets públicas e privadas.
- Múltiplas Availability Zones.
- Internet Gateway.
- Route Tables.
- NAT Gateway.
- Isolamento dos recursos privados.

### Amazon EKS

Cluster Kubernetes gerenciado utilizado para executar os cinco microsserviços.

O cluster utiliza:

- EKS.
- EC2 Worker Nodes.
- `t3.micro`.
- EKS Add-ons:
  - `vpc-cni`
  - `coredns`
  - `kube-proxy`
- OIDC Provider.
- IAM Roles para workloads Kubernetes.
- IRSA / Web Identity Federation.

### Amazon RDS PostgreSQL

Devido às limitações de quota do ambiente AWS Free Tier/Academy, os três bancos lógicos são distribuídos em **duas instâncias físicas RDS**:

```text
RDS 1
└── rds-auth
    └── auth_db

RDS 2
└── rds-flag
    ├── flag_db
    └── targeting_db
```

O `targeting_db` é criado posteriormente dentro da mesma instância PostgreSQL do `flag_db`.

### Amazon ElastiCache Redis

Redis utilizado pelo **Evaluation Service** para operações de baixa latência.

### Amazon SQS

Fila utilizada para desacoplar o processamento assíncrono entre:

```text
Evaluation Service
        |
        v
      SQS
        |
        v
Analytics Service
```

### Amazon DynamoDB

Tabela utilizada pelo Analytics Service para armazenamento de eventos:

```text
ToggleMasterAnalytics
```

com:

```text
Partition Key: event_id
```

### Amazon ECR

Cinco repositórios privados para as imagens Docker:

```text
auth-service
flag-service
targeting-service
evaluation-service
analytics-service
```

---

# 🔐 Gestão de Secrets

A infraestrutura utiliza o **AWS Secrets Manager** como fonte central de credenciais e informações sensíveis.

Nenhuma senha ou chave principal deve ser armazenada diretamente nos manifests Kubernetes ou no código dos microsserviços.

Os principais secrets são:

```text
tech-challenge/auth-master-key
tech-challenge/rds-auth
tech-challenge/rds-flag
```

## Auth Master Key

O Terraform gera automaticamente uma chave aleatória de 32 caracteres:

```hcl
resource "random_password" "auth_master_key" {
  length  = 32
  special = false
}
```

Essa chave é armazenada no Secrets Manager como:

```json
{
  "MASTER_KEY": "..."
}
```

A `MASTER_KEY` é utilizada pelo Auth Service para operações relacionadas à autenticação.

---

# 🔑 RDS Credentials

As credenciais dos bancos também são geradas automaticamente pelo Terraform.

Cada instância possui:

- username;
- password;
- engine;
- port;
- database name;
- host/endpoint.

Exemplo conceitual:

```json
{
  "username": "auth_user",
  "password": "...",
  "engine": "postgres",
  "port": 5432,
  "db_name": "auth_db",
  "host": "..."
}
```

As senhas são geradas utilizando o Terraform `random_password` e armazenadas no AWS Secrets Manager.

---

# 🔄 External Secrets Operator

O **External Secrets Operator (ESO)** é responsável por sincronizar secrets do AWS Secrets Manager para Kubernetes.

O fluxo é:

```text
AWS Secrets Manager
        |
        | GetSecretValue
        v
External Secrets Operator
        |
        v
Kubernetes Secret
        |
        v
Application Pod
```

O Terraform instala o External Secrets Operator através de Helm.

O ServiceAccount utilizado pelo operador recebe uma IAM Role específica através de:

```text
EKS OIDC
   +
IRSA / Web Identity
```

A IAM Role permite somente:

```text
secretsmanager:GetSecretValue
```

para os secrets necessários do ToggleMaster.

Isso evita armazenar credenciais AWS diretamente nos Pods.

---

# 🔐 EKS OIDC + IRSA

O cluster EKS possui um OIDC Identity Provider configurado pelo Terraform.

O OIDC permite que workloads Kubernetes assumam IAM Roles utilizando tokens de identidade emitidos pelo Kubernetes.

O fluxo é:

```text
Kubernetes ServiceAccount
          |
          | OIDC Token
          v
AWS STS
          |
          | AssumeRoleWithWebIdentity
          v
IAM Role
          |
          v
AWS Resource
```

No caso do External Secrets:

```text
external-secrets ServiceAccount
             |
             v
       EKS OIDC Provider
             |
             v
      AWS IAM Role
             |
             v
    AWS Secrets Manager
```

A IAM Role possui uma condição específica para o ServiceAccount:

```text
system:serviceaccount:external-secrets:external-secrets
```

Dessa forma, somente o ServiceAccount autorizado pode assumir a Role.

---

# 🚀 GitOps com Argo CD

O deployment dos microsserviços é gerenciado utilizando **Argo CD**.

O Terraform instala o Argo CD no namespace:

```text
argocd
```

Depois, uma `Application` chamada:

```text
toggle-prod
```

é criada no Argo CD.

A aplicação aponta para:

```text
GitHub
└── toggle-master-devops
    └── k8s/apps/toggle-prod
```

O Argo CD monitora essa estrutura e sincroniza os manifests Kubernetes com o cluster EKS.

---

# 🔄 Fluxo de Deployment

O fluxo completo é:

```text
Developer
    |
    | git push
    v
GitHub
    |
    v
toggle-master-devops
    |
    | Argo CD detects changes
    v
Argo CD
    |
    | Sync
    v
EKS
    |
    +---- Auth Service
    +---- Flag Service
    +---- Targeting Service
    +---- Evaluation Service
    +---- Analytics Service
```

O Argo CD utiliza:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
```

Isso significa que:

- alterações no Git podem ser sincronizadas automaticamente;
- recursos removidos do Git podem ser removidos do cluster;
- alterações manuais no cluster podem ser revertidas para o estado definido no Git.

---

# 🌐 NGINX Ingress Controller

O NGINX Ingress Controller é instalado através de Helm.

O serviço é configurado como:

```yaml
controller:
  service:
    type: LoadBalancer
```

Dessa forma, a AWS provisiona um Load Balancer para receber o tráfego externo destinado ao cluster.

O fluxo é:

```text
Internet
   |
   v
AWS Load Balancer
   |
   v
NGINX Ingress Controller
   |
   v
Kubernetes Services
   |
   v
Application Pods
```

---

# 📦 Estrutura do Terraform

```text
.
├── main.tf
├── variables.tf
├── outputs.tf
├── providers.tf
├── backend.tf
├── terraform.tfvars
│
└── modules/
    ├── vpc/
    │   └── Networking
    │
    ├── iam/
    │   └── IAM Roles e Policies
    │
    ├── eks/
    │   └── EKS Cluster + Node Groups + OIDC
    │
    ├── rds/
    │   └── PostgreSQL + Secrets Manager
    │
    ├── elasticache/
    │   └── Redis
    │
    ├── dynamodb/
    │   └── Analytics Database
    │
    ├── sqs/
    │   └── Message Queue
    │
    ├── ecr/
    │   └── Container Registries
    │
    ├── helm/
    │   ├── NGINX Ingress
    │   ├── Argo CD
    │   └── External Secrets
    │
    ├── external-secrets/
    │   └── IAM Role + Permissions
    │
    └── secrets/
        └── Auth Master Key
```

---

# 🛠️ Pré-requisitos

Antes de executar o projeto, instale:

- Terraform `>= 1.10.0`
- AWS CLI `>= 2.x`
- kubectl
- Docker
- Git

Também é necessário possuir credenciais AWS com permissões suficientes para criar os recursos utilizados pelo projeto.

Configuração inicial:

```bash
aws configure
```

Validação:

```bash
aws sts get-caller-identity
```

---

# ⚙️ Deploy da Infraestrutura

## 1. Criar o Bucket S3

O Terraform utiliza um backend remoto S3 para armazenar o state.

Exemplo:

```bash
aws s3api create-bucket \
  --bucket togglemaster-bucket-s3 \
  --region us-east-1
```

---

## 2. Inicializar o Terraform

```bash
terraform init
```

O backend utiliza:

```hcl
backend "s3" {
  bucket       = "togglemaster-bucket-s3"
  key          = "prod/togglemaster/terraform.tfstate"
  region       = "us-east-1"
  use_lockfile = true
}
```

O `use_lockfile = true` utiliza o mecanismo nativo de locking do S3 disponível nas versões recentes do Terraform, eliminando a necessidade de uma tabela DynamoDB exclusivamente para state locking.

---

## 3. Validar a configuração

```bash
terraform fmt -recursive
terraform validate
```

---

## 4. Criar o plano

```bash
terraform plan
```

---

## 5. Provisionar a infraestrutura

```bash
terraform apply -auto-approve
```

O Terraform irá provisionar os principais componentes:

```text
VPC
IAM
EKS
OIDC
RDS
Redis
SQS
DynamoDB
ECR
NGINX
Argo CD
External Secrets
AWS Secrets Manager
```

---

# 🔌 Conectando ao EKS

Após a criação do cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name togglemaster-eks
```

Verificar o contexto:

```bash
kubectl config current-context
```

Verificar os nodes:

```bash
kubectl get nodes
```

---

# 🔍 Validando os componentes Kubernetes

## Namespaces

```bash
kubectl get namespaces
```

Os principais namespaces esperados incluem:

```text
argocd
external-secrets
ingress-nginx
toggle-prod
```

---

## Argo CD

```bash
kubectl get pods -n argocd
```

Verificar a Application:

```bash
kubectl get applications -n argocd
```

Esperado:

```text
toggle-prod
```

---

## External Secrets

```bash
kubectl get pods -n external-secrets
```

Verificar os recursos:

```bash
kubectl get externalsecrets -A
```

---

## NGINX

```bash
kubectl get pods -n ingress-nginx
```

Verificar o Load Balancer:

```bash
kubectl get svc -n ingress-nginx
```

---

## ToggleMaster

```bash
kubectl get pods -n toggle-prod
```

Services:

```bash
kubectl get svc -n toggle-prod
```

---

# 🗄️ RDS e bancos de dados

A infraestrutura utiliza duas instâncias RDS devido à limitação de quota do ambiente AWS Free Tier/Academy.

### RDS Auth

```text
Instance: rds-auth
Database: auth_db
User: auth_user
```

### RDS Flag

```text
Instance: rds-flag
Database: flag_db
Database: targeting_db
User: flag_user
```

O `targeting_db` compartilha a mesma instância física do `flag_db`, mas permanece logicamente separado como database PostgreSQL.

---

# 🧩 Criação do targeting_db

Como o Terraform cria somente o database inicial definido em `db_name`, o `targeting_db` é criado posteriormente dentro da instância `rds-flag`.

É possível utilizar um Pod temporário contendo o cliente PostgreSQL:

```bash
kubectl run psql-check \
  --rm \
  -i \
  --tty \
  --image=postgres:15-alpine \
  -- bash
```

Conectar ao RDS:

```bash
psql \
  -h <RDS_FLAG_ENDPOINT> \
  -U flag_user \
  -d flag_db
```

Criar o database:

```sql
CREATE DATABASE targeting_db;
```

Validar:

```sql
\l
```

O resultado deverá apresentar:

```text
flag_db
targeting_db
```

na mesma instância PostgreSQL.

---

# 🔒 Segurança

A arquitetura utiliza os seguintes mecanismos de segurança:

### Secrets Manager

Credenciais e chaves sensíveis são armazenadas no AWS Secrets Manager.

### External Secrets

O Kubernetes não precisa armazenar as credenciais diretamente nos manifests versionados no Git.

### IRSA / OIDC

Pods podem receber permissões AWS sem utilizar Access Keys estáticas.

### IAM Least Privilege

O External Secrets Operator possui somente as permissões necessárias para leitura dos secrets autorizados.

### Private Subnets

RDS e Redis são executados em subnets privadas.

### Security Groups

O acesso ao PostgreSQL é restrito ao Security Group utilizado pelo EKS.

### Terraform State

O Terraform State é armazenado remotamente no S3.

---

# 🧱 Princípios da Infraestrutura

O projeto segue os seguintes princípios:

- Infrastructure as Code.
- Infraestrutura modularizada.
- GitOps.
- Immutable Infrastructure.
- Least Privilege.
- Secrets Management.
- Kubernetes orchestration.
- Automação através de Terraform.
- Deployment através de Argo CD.
- Separação entre infraestrutura e aplicação.

---

# ⚠️ Limitações do AWS Free Tier / Academy

Durante o desenvolvimento foi identificada uma limitação de quota para instâncias RDS PostgreSQL:

```text
InstanceQuotaExceeded
You reached the maximum number of instances available
with free plan accounts.
```

A arquitetura originalmente previa três instâncias:

```text
rds-auth
rds-flag
rds-targeting
```

Porém, para permanecer dentro da quota disponível, a arquitetura foi adaptada para:

```text
rds-auth
    └── auth_db

rds-flag
    ├── flag_db
    └── targeting_db
```

Essa alteração mantém a separação lógica dos bancos sem exigir uma terceira instância RDS.

---

# 🧹 Destruição da Infraestrutura

Para remover os recursos provisionados pelo Terraform:

```bash
terraform destroy -auto-approve
```

> **Atenção:** confirme sempre os recursos apresentados pelo `terraform plan` antes de executar operações destrutivas.

Como os recursos utilizam serviços AWS que podem gerar custos, recomenda-se executar o `terraform destroy` quando a infraestrutura não estiver mais sendo utilizada.

---

# 📌 Resumo da Arquitetura

```text
                         ┌───────────────────┐
                         │      GitHub       │
                         │   Application     │
                         │       Repo        │
                         └─────────┬─────────┘
                                   │
                                   │ GitOps
                                   ▼
                         ┌───────────────────┐
                         │      Argo CD      │
                         └─────────┬─────────┘
                                   │
                                   ▼
┌──────────────────────────────────────────────────────────────┐
│                           AWS / EKS                           │
│                                                              │
│  ┌────────┐ ┌────────┐ ┌────────────┐                       │
│  │  Auth  │ │  Flag  │ │  Targeting │                       │
│  └────────┘ └────────┘ └────────────┘                       │
│                                                              │
│  ┌────────────┐ ┌───────────┐                                │
│  │ Evaluation │ │ Analytics │                                │
│  └──────┬─────┘ └─────┬─────┘                                │
│         │             │                                      │
└─────────┼─────────────┼──────────────────────────────────────┘
          │             │
          ▼             ▼
      ┌───────┐      ┌─────┐
      │ Redis │      │ SQS │
      └───────┘      └──┬──┘
                         │
                         ▼
                    ┌──────────┐
                    │ DynamoDB │
                    └──────────┘

          ┌───────────────────────────────┐
          │       AWS Secrets Manager     │
          │                               │
          │ auth-master-key               │
          │ rds-auth                      │
          │ rds-flag                      │
          └───────────────┬───────────────┘
                          │
                          ▼
                 External Secrets
                          │
                          ▼
                Kubernetes Secrets
```

---

# 👥 Microsserviços

| Serviço | Responsabilidade | Infraestrutura |
|---|---|---|
| Auth Service | Autenticação e autorização | RDS `auth_db` |
| Flag Service | Gerenciamento de Feature Flags | RDS `flag_db` |
| Targeting Service | Segmentação e regras | RDS `targeting_db` |
| Evaluation Service | Avaliação de flags | Redis |
| Analytics Service | Telemetria e auditoria | SQS + DynamoDB |

---

# 📚 Tecnologias

- **Terraform**
- **AWS**
- **Amazon EKS**
- **Amazon EC2**
- **Amazon RDS PostgreSQL**
- **Amazon ElastiCache Redis**
- **Amazon SQS**
- **Amazon DynamoDB**
- **Amazon ECR**
- **AWS Secrets Manager**
- **IAM**
- **OIDC**
- **IRSA**
- **Kubernetes**
- **Helm**
- **NGINX Ingress Controller**
- **Argo CD**
- **External Secrets Operator**
- **Docker**
- **GitHub**

---

# 🎯 Objetivo

Este projeto tem como objetivo demonstrar a construção de uma infraestrutura AWS completa e automatizada para uma arquitetura de microsserviços, aplicando conceitos de:

- Cloud Infrastructure;
- Infrastructure as Code;
- Kubernetes;
- Containerization;
- CI/CD;
- GitOps;
- Secrets Management;
- IAM;
- IRSA;
- Observabilidade e mensageria;
- Escalabilidade;
- Segurança;
- Automação de deployments.

A infraestrutura pode ser completamente reproduzida através do Terraform, enquanto o estado desejado das aplicações Kubernetes é mantido no Git e sincronizado pelo Argo CD.
