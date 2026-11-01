# ------------------------------------------------------------------------------
# SELF-HEALING LAMBDA — ROLLING RESTART ON GRAFANA ALERT
# ------------------------------------------------------------------------------
# Receives a Grafana alerting webhook through API Gateway, validates the
# alert, and triggers a rolling restart of the target EKS Deployment.
# ------------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

# ------------------------------------------------------------------------------
# WEBHOOK BEARER TOKEN
# ------------------------------------------------------------------------------

resource "random_password" "webhook_token" {
  length  = 64
  upper   = false
  special = false
}

# ------------------------------------------------------------------------------
# LAMBDA EXECUTION IAM ROLE
# ------------------------------------------------------------------------------

resource "aws_iam_role" "lambda" {
  name = "self-healing-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# STS permission — the Lambda signs an STS GetCallerIdentity request to
# produce the EKS bearer token.
resource "aws_iam_role_policy" "sts" {
  name = "sts-getcalleridentity"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:GetCallerIdentity"
      Resource = "*"
    }]
  })
}

# ------------------------------------------------------------------------------
# EKS ACCESS ENTRY (Option A)
# ------------------------------------------------------------------------------
# Maps the Lambda role to the "self-healing" Kubernetes group. The RBAC
# RoleBinding (below) binds this group to the Role that grants patch/get
# on deployments in the target namespace.

resource "aws_eks_access_entry" "lambda" {
  cluster_name      = var.cluster_name
  principal_arn     = aws_iam_role.lambda.arn
  kubernetes_groups = ["self-healing"]
}

# ------------------------------------------------------------------------------
# KUBERNETES RBAC (Step 3)
# ------------------------------------------------------------------------------

resource "kubernetes_role_v1" "self_healing" {
  metadata {
    name      = "self-healing-restart"
    namespace = var.allowed_namespace
  }

  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["patch", "get"]
  }
}

resource "kubernetes_role_binding_v1" "self_healing" {
  metadata {
    name      = "self-healing-restart"
    namespace = var.allowed_namespace
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = "self-healing-restart"
  }

  subject {
    kind      = "Group"
    name      = "self-healing"
    api_group = "rbac.authorization.k8s.io"
  }
}

# ------------------------------------------------------------------------------
# LAMBDA FUNCTION (Step 4)
# ------------------------------------------------------------------------------

data "archive_file" "lambda" {
  type        = "zip"
  source_file = var.lambda_source_path
  output_path = "${path.module}/function.zip"
}

resource "aws_lambda_function" "self_healing" {
  function_name    = "self-healing-restart"
  runtime          = "python3.12"
  handler          = "app.handler"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      WEBHOOK_BEARER_TOKEN              = random_password.webhook_token.result
      ALLOWED_NAMESPACE                 = var.allowed_namespace
      EKS_CLUSTER_NAME                  = var.cluster_name
      EKS_CLUSTER_ENDPOINT              = var.eks_cluster_endpoint
      EKS_CLUSTER_CA_CERTIFICATE_BASE64 = var.eks_cluster_ca_certificate
      # AWS_REGION is reserved — Lambda injects it automatically at runtime.
    }
  }
}

# ------------------------------------------------------------------------------
# API GATEWAY HTTP API (Step 5)
# ------------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "webhook" {
  name          = "self-healing-webhook"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.webhook.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.self_healing.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "default" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "apigateway-invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.self_healing.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook.execution_arn}/*"
}
