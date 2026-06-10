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

resource "aws_iam_role" "lambda_execution_role" {
  name = "collectors-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
            Service = "lambda.amazonaws.com"
        }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  role = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}


resource "aws_iam_role" "discord_notifier_role" {
  name = "discord-notifier-lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "discord_notifier_vpc_access" {
  role       = aws_iam_role.discord_notifier_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_policy" "discord_notifier_policy" {
    name = "DiscordNotifierPolicy"
    path = "/"

    policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
            {
                Effect   = "Allow"
                Action   = [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
                ]
                Resource = "arn:aws:logs:*:*:*"
            }
        ]
    })
}

resource "aws_iam_role_policy_attachment" "discord_notifier_logs_attach" {
  role       = aws_iam_role.discord_notifier_role.name
  policy_arn = aws_iam_policy.discord_notifier_policy.arn
}

