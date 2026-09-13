# ------------------------------------------------------------------------------
# IAM ROLE - EVALUATION API KEY BOOTSTRAP
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "evaluation_bootstrap" {
  name = "${var.cluster_name}-evaluation-bootstrap-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "sts:AssumeRoleWithWebIdentity"
      ]

      Principal = {
        Federated = var.oidc_provider_arn
      }

      Condition = {
        StringEquals = {
          "${replace(var.oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:toggle-prod:evaluation-api-key-bootstrap"
        }
      }
    }]
  })
}

# ------------------------------------------------------------------------------
# PERMISSÕES PARA GERENCIAR A API KEY DO EVALUATION
# ------------------------------------------------------------------------------

resource "aws_iam_policy" "evaluation_bootstrap" {
  name = "${var.cluster_name}-evaluation-bootstrap"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "secretsmanager:GetSecretValue"
      ]

      Resource = [
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:tech-challenge/auth-master-key-*"
      ]
      }, {
      Effect = "Allow"

      Action = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:PutSecretValue"
      ]

      Resource = [
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:tech-challenge/evaluation-api-key-*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "evaluation_bootstrap" {
  role       = aws_iam_role.evaluation_bootstrap.name
  policy_arn = aws_iam_policy.evaluation_bootstrap.arn
}