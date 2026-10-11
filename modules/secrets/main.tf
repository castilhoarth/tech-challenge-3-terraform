resource "random_password" "auth_master_key" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "auth_master_key" {
  name                    = "tech-challenge/auth-master-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "auth_master_key" {
  secret_id = aws_secretsmanager_secret.auth_master_key.id

  secret_string = jsonencode({
    MASTER_KEY = random_password.auth_master_key.result
  })
}

resource "aws_secretsmanager_secret" "evaluation_api_key" {
  name                    = "tech-challenge/evaluation-api-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret" "evaluation_config" {
  name                    = "tech-challenge/evaluation-config"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "evaluation_config" {
  secret_id = aws_secretsmanager_secret.evaluation_config.id

  secret_string = jsonencode({
    REDIS_URL   = "redis://${var.redis_endpoint}:6379"
    AWS_SQS_URL = var.sqs_queue_url
    AWS_REGION  = "us-east-1"
  })
}