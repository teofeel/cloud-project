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
data "aws_region" "current" {}
data "aws_ec2_managed_prefix_list" "s3" {
  filter {
    name   = "prefix-list-name"
    values = ["com.amazonaws.${data.aws_region.current.region}.s3"]
  }
}
module "collectors_sg" {
  source  = "../../modules/security_groups"
  sg_name = var.collectors_sg_name
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = []
}

module "normalize_sg" {
  source  = "../../modules/security_groups"
  sg_name = var.normalize_sg_name
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = []
  egress_rules = [
    {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.s3.id]
    }
  ]
}

module "transform_sg" {
  source  = "../../modules/security_groups"
  sg_name = var.transform_sg_name
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = []
  egress_rules = [
    {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.s3.id]
    }
  ]
}


## gateway endpoint for s3
module "s3_gateway_endpoint" {
  source                  = "../../modules/gateway_endpoint"
  vpc_id                  = module.aws_vpc.vpc_id
  service_name            = "com.amazonaws.eu-west-1.s3"
  endpoint_type           = "Gateway"
  private_route_table_ids = [module.aws_vpc.private_route_table_id]
}

#s3 module
module "s3_bronze_layer" {
  source      = "../../modules/s3"
  bucket_name = var.s3_bronze_bucket_name
  environment = "dev"
}

module "s3_silver_layer" {
  source      = "../../modules/s3"
  bucket_name = var.s3_silver_bucket_name
  environment = "dev"
}

module "s3_gold_layer" {
  source      = "../../modules/s3"
  bucket_name = var.s3_gold_bucket_name
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
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [
          module.s3_bronze_layer.bucket_arn,
          module.s3_silver_layer.bucket_arn,
          module.s3_gold_layer.bucket_arn
        ]
      },
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = [
          "${module.s3_bronze_layer.bucket_arn}/*",
          "${module.s3_silver_layer.bucket_arn}/*",
          "${module.s3_gold_layer.bucket_arn}/*"
        ]
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
  output_zip_path  = var.hn_output_zip_path
  handler          = var.hn_handler

  iam_lambda_role_name       = data.terraform_remote_state.iam.outputs.lambda_role_name
  attach_s3_policy           = true
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


module "twitter_lambda" {
  source = "../../modules/lambda"

  function_name = var.twt_lambda_name
  #s3_bucket_name = var.s3_bronze_bucket_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.lambda_role_arn

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.collectors_sg.sg_id]

  #source_file_path = var.twt_source_file_path
  #output_zip_path = var.twt_output_zip_path
  source_file_path = var.twt_source_file_path
  output_zip_path  = var.twt_output_zip_path

  handler                    = var.twt_handler
  iam_lambda_role_name       = data.terraform_remote_state.iam.outputs.lambda_role_name
  lambda_s3_write_policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
  attach_s3_policy           = true

  environment_variables = {
    S3_BUCKET_NAME    = var.s3_bronze_bucket_name
    KAGGLE_USERNAME   = var.kaggle_username
    KAGGLE_KEY        = var.kaggle_key
    KAGGLE_CONFIG_DIR = "/tmp"
  }
}

module "twitter_daily_schedule" {
  source               = "../../modules/eventbridge"
  rule_name            = "twitter-collector-daily-rule"
  schedule_expression  = "cron(0 0 2 * ? *)"
  lambda_arn           = module.twitter_lambda.lambda_arn
  lambda_function_name = module.twitter_lambda.lambda_function_name
}

module "normalize_hn_lambda" {
  source = "../../modules/lambda"

  function_name   = var.normalize_hn_lambda_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.lambda_role_arn

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.normalize_sg.sg_id]

  source_file_path = var.normalize_hn_source_file_path
  output_zip_path  = var.normalize_hn_output_zip_path
  handler          = var.normalize_hn_lambda_handler

  iam_lambda_role_name       = data.terraform_remote_state.iam.outputs.lambda_role_name
  lambda_s3_write_policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
  attach_s3_policy           = true

  layers = [
    "arn:aws:lambda:eu-west-1:336392948345:layer:AWSSDKPandas-Python313:4"
  ]
  environment_variables = {
    BRONZE_BUCKET_NAME = var.s3_bronze_bucket_name
    SILVER_BUCKET_NAME = var.s3_silver_bucket_name
  }
}

module "normalize_x_lambda" {
  source = "../../modules/lambda"

  function_name   = var.normalize_x_lambda_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.lambda_role_arn

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.normalize_sg.sg_id]

  source_file_path = var.normalize_x_source_file_path
  output_zip_path  = var.normalize_x_output_zip_path
  handler          = var.normalize_x_lambda_handler

  iam_lambda_role_name       = data.terraform_remote_state.iam.outputs.lambda_role_name
  lambda_s3_write_policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
  attach_s3_policy           = true

  layers = [
    "arn:aws:lambda:eu-west-1:336392948345:layer:AWSSDKPandas-Python313:4"
  ]
  environment_variables = {
    BRONZE_BUCKET_NAME = var.s3_bronze_bucket_name
    SILVER_BUCKET_NAME = var.s3_silver_bucket_name
  }
}

module "transform_hn_lambda" {
  source = "../../modules/lambda"

  function_name   = var.transform_hn_lambda_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.lambda_role_arn

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.transform_sg.sg_id]

  source_file_path = var.transform_hn_source_file_path
  output_zip_path  = var.transform_hn_output_zip_path
  handler          = var.transform_hn_lambda_handler

  iam_lambda_role_name       = data.terraform_remote_state.iam.outputs.lambda_role_name
  lambda_s3_write_policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
  attach_s3_policy           = true

  layers = [
    "arn:aws:lambda:eu-west-1:336392948345:layer:AWSSDKPandas-Python313:4"
  ]

  environment_variables = {
    GOLD_BUCKET_NAME = var.s3_gold_bucket_name
  }

}

module "transform_x_lambda" {
  source = "../../modules/lambda"

  function_name   = var.transform_x_lambda_name
  lambda_role_arn = data.terraform_remote_state.iam.outputs.lambda_role_arn

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.transform_sg.sg_id]

  source_file_path = var.transform_x_source_file_path
  output_zip_path  = var.transform_x_output_zip_path
  handler          = var.transform_x_lambda_handler

  iam_lambda_role_name       = data.terraform_remote_state.iam.outputs.lambda_role_name
  lambda_s3_write_policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
  attach_s3_policy           = true

  layers = [
    "arn:aws:lambda:eu-west-1:336392948345:layer:AWSSDKPandas-Python313:4"
  ]

  environment_variables = {
    SILVER_BUCKET_NAME = var.s3_silver_bucket_name
    GOLD_BUCKET_NAME   = var.s3_gold_bucket_name
  }
}

#allow s3 bucket to invoke lambda
resource "aws_lambda_permission" "allow_s3_to_invoke_normalize_hn" {
  statement_id  = "AllowExecutionFromS3BucketHN"
  action        = "lambda:InvokeFunction"
  function_name = module.normalize_hn_lambda.lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_bronze_layer.bucket_arn
}

#s3 trigger
resource "aws_s3_bucket_notification" "bronze_bucket_notification" {
  bucket = module.s3_bronze_layer.bucket_id

  lambda_function {
    lambda_function_arn = module.normalize_hn_lambda.lambda_arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }


  depends_on = [aws_lambda_permission.allow_s3_to_invoke_normalize_hn]

}


resource "aws_lambda_function_event_invoke_config" "normalize_hn_on_success" {
  function_name          = module.normalize_hn_lambda.lambda_function_name
  maximum_retry_attempts = 0

  destination_config {
    on_success {
      destination = module.transform_hn_lambda.lambda_arn
    }
    on_failure {
      destination = module.sns_jobs_failure.sns_topic_arn
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "normalize_x_on_success" {
  function_name          = module.normalize_x_lambda.lambda_function_name
  maximum_retry_attempts = 0

  destination_config {
    on_success {
      destination = module.transform_x_lambda.lambda_arn
    }
    on_failure {
      destination = module.sns_jobs_failure.sns_topic_arn
    }
  }
}

resource "aws_lambda_permission" "allow_normalize_hn_to_invoke_transform" {
  statement_id  = "AllowNormalizeHNInvokeTransform"
  action        = "lambda:InvokeFunction"
  function_name = module.transform_hn_lambda.lambda_function_name
  principal     = "lambda.amazonaws.com"
  source_arn    = module.normalize_hn_lambda.lambda_arn
}

resource "aws_lambda_permission" "allow_normalize_x_to_invoke_transform" {
  statement_id  = "AllowNormalizeXInvokeTransform"
  action        = "lambda:InvokeFunction"
  function_name = module.transform_x_lambda.lambda_function_name
  principal     = "lambda.amazonaws.com"
  source_arn    = module.normalize_x_lambda.lambda_arn
}

resource "aws_iam_policy" "lambda_invoke_transform_policy" {
  name = "LambdaInvokeTransformPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "lambda:InvokeFunction"
      Resource = [
        module.transform_hn_lambda.lambda_arn,
        module.transform_x_lambda.lambda_arn
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "attach_invoke_transform_policy" {
  role       = data.terraform_remote_state.iam.outputs.lambda_role_name
  policy_arn = aws_iam_policy.lambda_invoke_transform_policy.arn
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

  function_name        = var.discord_notification_lambda_name
  lambda_role_arn      = data.terraform_remote_state.iam.outputs.discord_notifier_role_arn
  iam_lambda_role_name = data.terraform_remote_state.iam.outputs.discord_notifier_role_name

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.notifier_sg.sg_id]

  source_file_path = var.discord_notification_file_path
  output_zip_path  = var.discord_notification_zip_path
  handler          = var.discord_notification_lambda_handler

  lambda_s3_write_policy_arn = null
  attach_s3_policy           = false

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


module "sqs_jobs_failure" {
  source                     = "../../modules/sqs"
  queue_name                 = "job-failures-queue"
  visibility_timeout_seconds = 900
}

module "sns_jobs_failure" {
  source = "../../modules/sns"

  sns_topic_name       = "job-failures"
  sns_protocol         = "sqs"
  sns_endpoint         = module.sqs_jobs_failure.sqs_queue_arn
  raw_message_delivery = true
}

resource "aws_iam_policy" "lambda_sns_publish_policy" {
  name = "LambdaSNSPublishPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sns:Publish"
      Resource = module.sns_jobs_failure.sns_topic_arn
    }]
  })
}

resource "aws_sqs_queue_policy" "queue_policy" {
  queue_url = module.sqs_jobs_failure.sqs_queue_url

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowSNSToSendMessage",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "sns.amazonaws.com"
        },
        "Action" : "sqs:SendMessage",
        "Resource" : module.sqs_jobs_failure.sqs_queue_arn,
        "Condition" : {
          "ArnEquals" : {
            "aws:SourceArn" : module.sns_jobs_failure.sns_topic_arn
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_sns_publish_policy" {
  role       = data.terraform_remote_state.iam.outputs.lambda_role_name
  policy_arn = aws_iam_policy.lambda_sns_publish_policy.arn
}

resource "aws_iam_role_policy" "discord_lambda_sqs_policy" {
  name = "DiscordLambdaSQSPolicy"
  role = data.terraform_remote_state.iam.outputs.discord_notifier_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = [module.sqs_jobs_failure.sqs_queue_arn]
      }
    ]
  })
}
resource "aws_lambda_event_source_mapping" "sqs_to_lambda" {
  event_source_arn = module.sqs_jobs_failure.sqs_queue_arn
  function_name    = module.discord_notification_lambda.lambda_function_name
  batch_size       = 10
  enabled          = true
}

resource "aws_lambda_function_event_invoke_config" "hacker_news_on_failure" {
  function_name          = module.hacker_news_lambda.lambda_function_name
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = module.sns_jobs_failure.sns_topic_arn
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "twitter_on_failure" {
  function_name          = module.twitter_lambda.lambda_function_name
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = module.sns_jobs_failure.sns_topic_arn
    }
  }
}


resource "aws_lambda_function_event_invoke_config" "transform_x_on_failure" {
  function_name          = module.transform_x_lambda.lambda_function_name
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = module.sns_jobs_failure.sns_topic_arn
    }
  }
}

resource "aws_lambda_function_event_invoke_config" "transform_hn_on_failure" {
  function_name          = module.transform_hn_lambda.lambda_function_name
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = module.sns_jobs_failure.sns_topic_arn
    }
  }
}

module "visualization_module" {
  source = "../../modules/superset"

  vpc_id               = module.aws_vpc.vpc_id
  vpc_public_subnet_id = module.aws_vpc.public_subnet_id
  db_password          = var.db_password
  injector_cidr_blocks = [var.main_vpc_cidr_block]
}

module "injector_sg" {
  source  = "../../modules/security_groups"
  sg_name = var.injector_sg_name
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = []
  egress_rules = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [var.main_vpc_cidr_block]
    },
    {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      prefix_list_ids = [data.aws_ec2_managed_prefix_list.s3.id]
    }
  ]
}

resource "aws_iam_policy" "lambda_s3_gold_read_policy" {
  name        = "LambdaS3GoldReadPolicy"
  description = "Readonly access to gold for injector lambda"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [module.s3_gold_layer.bucket_arn]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = ["${module.s3_gold_layer.bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "attach_gold_read_to_injector_role" {
  role       = data.terraform_remote_state.iam.outputs.injector_role_name
  policy_arn = aws_iam_policy.lambda_s3_gold_read_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_sns_to_injector_role" {
  role       = data.terraform_remote_state.iam.outputs.injector_role_name
  policy_arn = aws_iam_policy.lambda_sns_publish_policy.arn
}

resource "null_resource" "build_injector_layer" {
  triggers = {
    always_run = "${timestamp()}"
  }

  provisioner "local-exec" {
    interpreter = ["powershell", "-Command"]
    command     = "Remove-Item -Force -Recurse ../../../build/injector-layer -ErrorAction SilentlyContinue; mkdir -Force ../../../build/injector-layer/python; pip install --platform manylinux_2_28_x86_64 --target ../../../build/injector-layer/python --only-binary=:all: --python-version 3.13 pg8000"
  }
}

data "archive_file" "injector_layer_zip" {
  depends_on  = [null_resource.build_injector_layer]
  type        = "zip"
  source_dir  = abspath("../../../build/injector-layer")
  output_path = abspath("injector_layer.zip")
}

resource "aws_lambda_layer_version" "injector_deps" {
  filename            = data.archive_file.injector_layer_zip.output_path
  layer_name          = "injector-sqlalchemy-psycopg2"
  compatible_runtimes = ["python3.13"]
  source_code_hash    = data.archive_file.injector_layer_zip.output_base64sha256
}

module "injector_lambda" {
  source = "../../modules/lambda"

  function_name        = var.injector_lambda_name
  lambda_role_arn      = data.terraform_remote_state.iam.outputs.injector_role_arn
  iam_lambda_role_name = data.terraform_remote_state.iam.outputs.injector_role_name

  private_subnet_ids = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.injector_sg.sg_id]

  source_file_path = var.injector_lambda_file_path
  output_zip_path  = var.injector_lambda_output_zip
  handler          = var.injector_lambda_handler

  lambda_s3_write_policy_arn = null
  attach_s3_policy           = false

  layers = [
    "arn:aws:lambda:eu-west-1:336392948345:layer:AWSSDKPandas-Python313:4",
    aws_lambda_layer_version.injector_deps.arn
  ]

  environment_variables = {
    DB_USER     = var.db_user
    DB_PASSWORD = var.db_password
    DB_HOST     = module.visualization_module.db_host
    DB_NAME     = var.db_name
  }
}

resource "aws_lambda_permission" "allow_s3_to_invoke_injector" {
  statement_id  = "AllowExecutionFromS3BucketHN"
  action        = "lambda:InvokeFunction"
  function_name = module.injector_lambda.lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = module.s3_gold_layer.bucket_arn
}


resource "aws_s3_bucket_notification" "gold_bucket_notification" {
  bucket = module.s3_gold_layer.bucket_id

  lambda_function {
    lambda_function_arn = module.injector_lambda.lambda_arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".parquet"
  }

  depends_on = [aws_lambda_permission.allow_s3_to_invoke_injector]
}


resource "aws_lambda_function_event_invoke_config" "injector_on_failure" {
  function_name          = module.injector_lambda.lambda_function_name
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = module.sns_jobs_failure.sns_topic_arn
    }
  }
}