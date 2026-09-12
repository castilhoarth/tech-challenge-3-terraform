# 1. Networking (VPC, Subnets Públicas e Privadas, NAT Gateway)
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr             = "10.0.0.0/16"
  public_subnets_cidr  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets_cidr = ["10.0.10.0/24", "10.0.11.0/24"]
  availability_zones   = ["us-east-1a", "us-east-1b"]
  cluster_name         = var.cluster_name
}

# 2. IAM (Roles do EKS e Permissões de Pods / IRSA)
module "iam" {
  source = "./modules/iam"

  cluster_name = var.cluster_name
}

# 2. Kubernetes Cluster (EKS & NOde Groups)
module "eks" {
  source = "./modules/eks"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.public_subnet_ids

  # Roles de IAM dinâmicas criadas no módulo IAM
  cluster_role_arn = module.iam.eks_cluster_role_arn
  node_role_arn    = module.iam.eks_node_role_arn

  instance_types = ["t3.micro"]
  desired_size   = 10
  min_size       = 8
  max_size       = 12
}

#instalação do nginx e argoCD e external accounts
module "helm" {
  source = "./modules/helm"

  external_secrets_role_arn = module.external_secrets.role_arn

  depends_on = [
    module.eks,
    module.external_secrets
  ]
}

# 3. Banco de Dados (3 RDS PostgreSQL Isolados)
module "rds" {
  source = "./modules/rds"

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  subnet_ids            = module.vpc.private_subnet_ids
  eks_security_group    = module.eks.cluster_security_group_id
  eks_security_group_id = module.eks.cluster_security_group_id

  instances = {
    auth = {
      username  = "auth_user"
      databases = ["auth_db"]
    }

    flag = {
      username = "flag_user"
      databases = [
        "flag_db",
        "targeting_db"
      ]
    }
  }
}

module "secrets" {
  source = "./modules/secrets"
}

# 5 . Cache (Elasticache Redis - Evaluation Service) 
module "elasticache" {
  source = "./modules/elasticache"

  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  subnet_ids            = module.vpc.private_subnet_ids
  eks_security_group    = module.eks.cluster_security_group_id
  eks_security_group_id = module.eks.cluster_security_group_id
  node_type             = "cache.t3.micro"
}

# 6. Banco NoSQL (DynamoDB - Analytics Service)
module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = "ToggleMasterAnalytics"
  hash_key   = "event_id"
}

# 4. Mensageria (SQS)
module "sqs" {
  source = "./modules/sqs"

  queue_name = "togglemaster-analytics-queue"
}

# 5. Repositórios de Imagens Docker (ECR)
module "ecr" {
  source = "./modules/ecr"

  repository_names = [
    "auth-service",
    "flag-service",
    "targeting-service",
    "evaluation-service",
    "analytics-service",
  ]
}

module "external_secrets" {
  source = "./modules/external-secrets"

  cluster_name      = var.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_issuer_url   = module.eks.oidc_issuer_url

  depends_on = [module.eks]
}