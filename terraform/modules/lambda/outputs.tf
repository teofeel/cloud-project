output "lambda_arn" {
  value       = aws_lambda_function.this.arn
  description = "amazon resoursce name (ARN) for created lambda"
}

output "lambda_function_name" {
  value       = aws_lambda_function.this.function_name
  description = "Lambda function name"
}