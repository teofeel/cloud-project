resource "aws_iam_policy" "admin_policy" {
    name = "AdminUserPolicy"
    policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": "*",
                "Resource": "*"
            }
        ]
    }
    EOF
}


resource "aws_iam_user" "admins" {
    for_each = toset(var.admin_users)
    name = each.value
    tags = {
        Description = "Coworkers on this project"
    }
}


resource "aws_iam_group" "admin_group" {
    name = var.admin_group
}


resource "aws_iam_group_policy_attachment" "admin_group_attachment" {
    group = aws_iam_group.admin_group.name
    policy_arn = aws_iam_policy.admin_policy.arn
}


resource "aws_iam_group_membership" "admins" {
  name = "admin-group-membership"

  users = [
    for user in aws_iam_user.admins : user.name
  ]

  group = aws_iam_group.admin_group.name
}
