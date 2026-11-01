output "rds_endpoints" {
  description = "Endpoints das instâncias RDS"
  value       = module.rds.endpoints
}

output "redis_endpoint" {
  value = module.elasticache.redis_endpoint
}

output "webhook_url" {
  description = "API Gateway webhook URL for Grafana"
  value       = module.self_healing.webhook_url
}