provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project      = "TechChallenge"
      Application  = "ToggleMaster"
      Phase        = "Fase 3"
      Environment  = "Production"
      ManagedBy    = "Terraform"
      Architecture = "Microservices"
    }
  }
}

data "aws_eks_cluster" "main" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_id
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.main.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.main.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.main.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.main.token
}