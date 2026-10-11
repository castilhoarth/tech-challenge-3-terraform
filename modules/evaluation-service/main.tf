data "aws_caller_identity" "current" {}

resource "aws_iam_role" "evaluation_service" {
  name = "${var.cluster_name}-evaluation-service-role"

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

          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:toggle-prod:evaluation-service"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "evaluation_service" {
  name = "${var.cluster_name}-evaluation-service"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "sqs:SendMessage"
      ]

      Resource = var.sqs_queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "evaluation_service" {
  role       = aws_iam_role.evaluation_service.name
  policy_arn = aws_iam_policy.evaluation_service.arn
}