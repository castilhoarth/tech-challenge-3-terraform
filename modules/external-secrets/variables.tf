variable "cluster_name" {
  description = "Nome do cluster EKS"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN do OIDC Provider do EKS"
  type        = string
}

variable "oidc_issuer_url" {
  description = "URL do OIDC Provider do EKS"
  type        = string
}