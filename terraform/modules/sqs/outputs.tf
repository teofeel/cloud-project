output "sqs_queue_arn" {
  description = "The ARN of the SQS queue"
  value       = aws_sqs_queue.queue.arn
}

output "sqs_queue_url" {
    value = aws_sqs_queue.queue.url
}