resource "aws_cloudwatch_event_rule" "event_rule" {
  name        = var.event_rule_name

  event_pattern = jsonencode({
    source      = var.event_rule_source
    detail-type = var.event_detail_types
    resources = var.resource_arns 
    detail = {
      status = var.event_statuses
    }
  })
}

resource "aws_cloudwatch_event_target" "event_target" {
  rule      = aws_cloudwatch_event_rule.event_rule.name
  target_id = var.target_id
  arn       = var.sns_topic_arn
}

