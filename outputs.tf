output "rds_endpoints" {
  description = "Endpoints das instâncias RDS"
  value       = module.rds.endpoints
}