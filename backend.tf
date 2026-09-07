terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }


    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.17"
    }
  }

  # Configuração do Remote State no S3 Backend
  backend "s3" {
    bucket       = "togglemaster-bucket-s3"
    key          = "prod/togglemaster/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true # Nativo a partir do Terraform 1.10 (elimina necessidade de tabela DynamoDB legada para lock) 
  }
}