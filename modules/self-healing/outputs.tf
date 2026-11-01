output "webhook_url" {
  description = "API Gateway webhook URL for Grafana"
  value       = aws_apigatewayv2_api.webhook.api_endpoint
}

output "lambda_function_name" {
  description = "Name of the self-healing Lambda function"
  value       = aws_lambda_function.self_healing.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = aws_iam_role.lambda.arn
}
