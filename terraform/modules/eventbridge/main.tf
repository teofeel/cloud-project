resource "aws_cloudwatch_event_rule" "this" {
  name = var.rule_name
  schedule_expression = var.schedule_expression
  event_pattern = var.event_pattern

}

resource "aws_cloudwatch_event_target" "this" {
  rule = aws_cloudwatch_event_rule.this.name
  target_id = "TargetLambda"
  arn = var.lambda_arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id = "AllowExecutionFromEventBridge"
  action = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal = "events.amazonaws.com"
  source_arn = aws_cloudwatch_event_rule.this.arn
}