terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

# import iam config from global/iam workspace
data "terraform_remote_state" "iam" {
  backend = "local"
  config = {
    path = "../../global/iam/terraform.tfstate"
  }
}

# here we are creating VPC and lambda, S3 services using created modules from them
module "aws_vpc" {
  source                    = "../../modules/vpc"
  main_vpc_cidr_block       = var.main_vpc_cidr_block
  main_vpc_instance_tenancy = var.main_vpc_instance_tenancy
  public_subnet_cidr_block  = var.public_subnet_cidr_block
  subnet_map_on_launch      = var.public_subnet_map_on_launch
  route_table_cidr_block    = var.route_table_cidr_block
  private_subnet_cidr_block = var.private_subnet_cidr_block
}

# create fck-nat-ami security group
module "nat_sg" {
  source  = "../../modules/security_groups"
  sg_name = var.nat_sg_name
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = [{
    from_port   = var.nat_sg_ingress_from_port
    to_port     = var.nat_sg_ingress_to_port
    protocol    = var.nat_sg_ingress_protocol
    cidr_blocks = [var.private_subnet_cidr_block]
  }]
}

# create fck-nat-ami
module "fck_nat" {
  source  = "RaJiska/fck-nat/aws"
  version = "~> 1.4.0"

  name      = var.nat_ec2_instance_name
  vpc_id    = module.aws_vpc.vpc_id
  subnet_id = module.aws_vpc.public_subnet_id

  update_route_tables = false

  instance_type                 = var.nat_ec2_instance_type
  additional_security_group_ids = [module.nat_sg.sg_id]
}

resource "aws_route" "private_internet_access" {
  route_table_id         = module.aws_vpc.private_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.fck_nat.eni_id

  depends_on = [module.fck_nat] 
}


# create sg for collectors lambda that will send req to tw and hn
module "collectors_sg" {
  source  = "../../modules/security_groups"
  sg_name = var.collectors_sg_name
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = []
}

#s3 module
module "s3_bronze_layer" {
  source      = "../../modules/s3"
  bucket_name = var.s3_bronze_bucket_name
  environment = "dev"
}

resource "aws_iam_policy" "lambda_s3_write_policy" {
  name        = "LambdaS3BronzeWritePolicy"
  path        = "/"
  description = "Allowing lambda to write in s3"


  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject",]
        Resource = "${module.s3_bronze_layer.bucket_arn}/*" 
      },
    ]
  })
}

module "hacker_news_lambda" {
  source = "../../modules/lambda"

  function_name = var.hacker_news_lambda_name
  #s3_bucket_name = var.s3_bronze_bucket_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.lambda_role_arn

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.collectors_sg.sg_id]

  source_file_path = var.hn_source_file_path
  output_zip_path = var.hn_output_zip_path
  handler = var.hn_handler

  iam_lambda_role_name = data.terraform_remote_state.iam.outputs.lambda_role_name
  lambda_s3_write_policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
  
  environment_variables = {
    S3_BUCKET_NAME = var.s3_bronze_bucket_name
  }
}

module "hacker_news_daily_schedule" {
  source               = "../../modules/eventbridge"
  rule_name            = "hacker-news-collector-daily-rule"
  schedule_expression  = "cron(0 1 * * ? *)"
  lambda_arn           = module.hacker_news_lambda.lambda_arn
  lambda_function_name = module.hacker_news_lambda.lambda_function_name
}
locals {
  twt_build_dir = "${path.module}/../../../code/twitter_build"
}

resource "null_resource" "twitter_lambda_build" {
  triggers = {
    source_hash = filemd5(var.twt_source_file_path)
  }

 provisioner "local-exec" {
    command = <<EOT
      pip install kaggle -t ../../../code/twitter_build/ --quiet
      copy ..\..\..\code\twitter_lambda.py ..\..\..\code\twitter_build\
    EOT
  }
}


module "twitter_lambda" {
  source = "../../modules/lambda"

  function_name = var.twt_lambda_name
  #s3_bucket_name = var.s3_bronze_bucket_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.lambda_role_arn

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.collectors_sg.sg_id]

  #source_file_path = var.twt_source_file_path
  #output_zip_path = var.twt_output_zip_path
  source_file_path = var.twt_source_file_path  # still needed if build_dir == ""
  build_dir        = local.twt_build_dir        # this takes precedence
  output_zip_path  = var.twt_output_zip_path

  handler = var.twt_handler
  iam_lambda_role_name = data.terraform_remote_state.iam.outputs.lambda_role_name
  lambda_s3_write_policy_arn = aws_iam_policy.lambda_s3_write_policy.arn

  environment_variables = {
    S3_BUCKET_NAME = var.s3_bronze_bucket_name
    KAGGLE_USERNAME = var.kaggle_username
    KAGGLE_KEY      = var.kaggle_key
    KAGGLE_CONFIG_DIR   = "/tmp"
  }
}

module "twitter_daily_schedule" {
  source               = "../../modules/eventbridge"
  rule_name            = "twitter-collector-daily-rule"
  schedule_expression  = "cron(0 0 2 * ? *)" 
  lambda_arn           = module.twitter_lambda.lambda_arn
  lambda_function_name = module.twitter_lambda.lambda_function_name
}



# Notification SG and Lambda impl
module "notifier_sg" {
  source  = "../../modules/security_groups"
  sg_name = "notifier-sg"
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = []

  egress_rules = [{
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }]
}

module "discord_notification_lambda" {
  source = "../../modules/lambda"

  function_name = var.discord_notification_lambda_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.discord_notifier_role_arn
  iam_lambda_role_name = data.terraform_remote_state.iam.outputs.discord_notifier_role_name

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.notifier_sg.sg_id]

  source_file_path = var.discord_notification_file_path
  output_zip_path  = var.discord_notification_zip_path
  handler          = var.discord_notification_lambda_handler

  lambda_s3_write_policy_arn = null

  environment_variables = {
    DISCORD_WEBHOOK_URL = var.discord_webhook_url
  }
}

resource "aws_iam_policy" "lambda_invoke_discord_policy" {
  name = "LambdaInvokeDiscordNotifierPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = module.discord_notification_lambda.lambda_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_invoke_discord_policy" {
  role       = data.terraform_remote_state.iam.outputs.lambda_role_name
  policy_arn = aws_iam_policy.lambda_invoke_discord_policy.arn
}


resource "aws_lambda_function_event_invoke_config" "hacker_news_on_failure" {
  function_name = module.hacker_news_lambda.lambda_function_name

  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = module.discord_notification_lambda.lambda_arn
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "twitter_on_failure" {
  function_name = module.twitter_lambda.lambda_function_name

  maximum_retry_attempts = 0
  destination_config {
    on_failure {
      destination = module.discord_notification_lambda.lambda_arn
    }
  }
}

resource "aws_lambda_permission" "allow_lambda_destination" {
  statement_id  = "AllowLambdaDestinationInvoke"
  action        = "lambda:InvokeFunction"
  function_name = module.discord_notification_lambda.lambda_function_name
  principal     = "lambda.amazonaws.com"
  source_arn    = module.hacker_news_lambda.lambda_arn
}