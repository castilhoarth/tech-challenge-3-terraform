output "webhook_url" {
  description = "API Gateway webhook URL for Grafana"
  value       = "https://${aws_apigatewayv2_api.webhook.id}.execute-api.${var.aws_region}.amazonaws.com/"
}

output "webhook_bearer_token" {
  description = "Bearer token for Grafana webhook authentication"
  value       = random_password.webhook_token.result
  sensitive   = true
}

output "lambda_function_name" {
  description = "Name of the self-healing Lambda function"
  value       = aws_lambda_function.self_healing.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda.arn
}
