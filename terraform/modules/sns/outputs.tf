output "sns_arn" {
    value = aws_sns_topic_subscription.sns_topic_subscription.arn
}

output "sns_topic_arn" {
    value = aws_sns_topic.sns_topic.arn
}