variable "external_secrets_role_arn" {
  description = "ARN da IAM Role do External Secrets Operator"
  type        = string
}

variable "keda_role_arn" {
  type = string
}