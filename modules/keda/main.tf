resource "aws_iam_role" "keda" {
  name = "${var.cluster_name}-keda-role"

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

          "${replace(var.oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:keda:keda-operator"
        }
      }
    }]
  })
}

resource "aws_iam_policy" "keda" {
  name = "${var.cluster_name}-keda"

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Action = [
        "sqs:GetQueueAttributes"
      ]

      Resource = var.sqs_queue_arn
    }]
  })
}

resource "aws_iam_role_policy_attachment" "keda" {
  role       = aws_iam_role.keda.name
  policy_arn = aws_iam_policy.keda.arn
}