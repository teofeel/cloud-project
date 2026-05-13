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