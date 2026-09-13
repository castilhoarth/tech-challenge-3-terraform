resource "aws_iam_role" "analytics_service" {
  name = "${var.cluster_name}-analytics-service-role"

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

          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:toggle-prod:analytics-service"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "analytics_service" {
  name = "${var.cluster_name}-analytics-service"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes"
      ]

      Resource = var.sqs_queue_arn
      }, {
      Effect = "Allow"

      Action = [
        "dynamodb:PutItem"
      ]

      Resource = var.dynamodb_table_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "analytics_service" {
  role       = aws_iam_role.analytics_service.name
  policy_arn = aws_iam_policy.analytics_service.arn
}