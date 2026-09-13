resource "aws_dynamodb_table" "analytics" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST" # On-demand para custo otimizado
  hash_key     = "event_id"        # Chave primária da tabela

  attribute {
    name = "event_id"
    type = "S" # Tipo String
  }

  tags = {
    Name = var.table_name
  }
}