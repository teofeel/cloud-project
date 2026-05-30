output "bucket_id" {
  value       = aws_s3_bucket.this.id
  description = "name(id) of created bucket"
}

output "bucket_arn" {
  value       = aws_s3_bucket.this.arn
  description = "amazon resoursce name (ARN) for created bucket"
}