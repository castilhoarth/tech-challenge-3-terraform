output "role_arn" {
  description = "ARN da IAM Role usada pelo External Secrets Operator"
  value       = aws_iam_role.external_secrets.arn
}