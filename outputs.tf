output "rds_endpoints" {
  description = "Endpoints das instâncias RDS"
  value       = module.rds.endpoints
}

output "redis_endpoint" {
  value = module.elasticache.redis_endpoint
}