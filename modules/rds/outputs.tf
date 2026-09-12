output "endpoints" {
  description = "Endpoints das instâncias RDS"
  value = {
    for key, db in aws_db_instance.postgres :
    key => db.endpoint
  }
}