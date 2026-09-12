# ------------------------------------------------------------------------------
# IAM ROLE - EXTERNAL SECRETS OPERATOR
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

resource "aws_iam_role" "external_secrets" {
  name = "${var.cluster_name}-external-secrets-role"

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
          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }]
  })
}

# ------------------------------------------------------------------------------
# PERMISSÃO PARA LER O AWS SECRETS MANAGER
# ------------------------------------------------------------------------------

resource "aws_iam_policy" "external_secrets" {
  name = "${var.cluster_name}-external-secrets"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "secretsmanager:GetSecretValue"
      ]

      Resource = [
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:tech-challenge/auth-master-key-*",
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:tech-challenge/rds-auth-*",
        "arn:aws:secretsmanager:us-east-1:${data.aws_caller_identity.current.account_id}:secret:tech-challenge/rds-flag-*"
    ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "external_secrets" {
  role       = aws_iam_role.external_secrets.name
  policy_arn = aws_iam_policy.external_secrets.arn
}