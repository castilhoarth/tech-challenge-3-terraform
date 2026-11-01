variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "eks_cluster_endpoint" {
  description = "EKS cluster API endpoint URL"
  type        = string
}

variable "eks_cluster_ca_certificate" {
  description = "Base64-encoded EKS cluster CA certificate"
  type        = string
}

variable "allowed_namespace" {
  description = "Kubernetes namespace where the Lambda can restart deployments"
  type        = string
}

variable "lambda_source_path" {
  description = "Path to the Lambda handler source file (app.py)"
  type        = string
}
