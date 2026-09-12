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