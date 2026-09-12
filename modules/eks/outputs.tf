output "cluster_id" {
  description = "Nome/ID do cluster EKS"
  value       = aws_eks_cluster.main.id
}

output "cluster_endpoint" {
  description = "Endpoint do API Server do EKS"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_security_group_id" {
  description = "ID do Security Group atribuído ao cluster EKS"
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}

output "oidc_provider_arn" {
  description = "ARN do OIDC Provider usado pelo EKS"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer_url" {
  description = "URL do OIDC Provider do EKS"
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
}