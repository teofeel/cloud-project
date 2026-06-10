data "archive_file" "lambda_zip" {
  type = "zip"
  #source_file = var.source_file_path
  #output_path = var.output_zip_path

  source_dir  = var.build_dir != "" ? var.build_dir : null
  source_file = var.build_dir == "" ? var.source_file_path : null
  output_path = var.output_zip_path
}

resource "aws_lambda_function" "this" {
    function_name = var.function_name
    runtime = "python3.13"
    handler = var.handler
    role = var.lambda_role_arn
    filename = data.archive_file.lambda_zip.output_path
    source_code_hash = data.archive_file.lambda_zip.output_base64sha256
    timeout = 900
    memory_size = 3008

    ephemeral_storage {
      size = 10240
    }

    vpc_config {
      subnet_ids = var.private_subnet_ids
      security_group_ids = var.security_group_ids
    }

    layers = var.layers

    #environment {
    #  variables = {
    #    S3_BUCKET_NAME = var.s3_bucket_name
    #  }
    #}

    dynamic "environment" {
      for_each = length(var.environment_variables) > 0 ? [var.environment_variables] : []
      content {
        variables = var.environment_variables
      }
    }
}

resource "aws_iam_role_policy_attachment" "attach_s3_policy_to_lambda_role" {
  #role = data.terraform_remote_state.iam.outputs.lambda_role_name
  #policy_arn = aws_iam_policy.lambda_s3_write_policy.arn
  count = var.lambda_s3_write_policy_arn != null ? 1 : 0  

  role = var.iam_lambda_role_name
  policy_arn = var.lambda_s3_write_policy_arn
}