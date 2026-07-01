output "admin_group_arn"{
    value = aws_iam_group.admin_group.arn
}

output "admin_user_names" {
  value = [for u in aws_iam_user.admins : u.name]
}

output "admin_users_arn" {
    value = [for user in aws_iam_user.admins : user.arn]
}

output "admin_user_map" {
    value = {for name, user in aws_iam_user.admins : name => user.arn}
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda_execution_role.arn
}

output "lambda_role_name" {
  value = aws_iam_role.lambda_execution_role.name
}

output "injector_role_arn" {
  value = aws_iam_role.injector_lambda_role.arn
}

output "injector_role_name" {
  value = aws_iam_role.injector_lambda_role.name
}

output "discord_notifier_role_arn" {
  value = aws_iam_role.discord_notifier_role.arn
}

output "discord_notifier_role_name" {
  value = aws_iam_role.discord_notifier_role.name
}