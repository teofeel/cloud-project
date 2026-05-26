variable "function_name" {
  type = string
  description = "lambda function name"
}

variable "source_file_path" {
  type = string
  description = "Path to code for the lambda"
}

variable "output_zip_path" {
  type = string
  description = "Path to where temporary zip file will be placed"
}

variable "handler" {
  type = string
  description = "Function name of the lambda handler"
}

variable "lambda_role_arn" {
  type = string
  description = "ARN role that gives the lambda permissions"
}

variable "s3_bucket_name" {
  type = string
  description = "S3 bucket name that the lambda writes data to"
}

variable "security_group_ids" {
  type = list(string)
  description = "ID of the security group for the lambda"
}

variable "private_subnet_ids" {
  type = list(string)
  description = "List of the private subnets inside the VPC"
}

variable lambda_s3_write_policy_arn{
  type = string
}

variable iam_lambda_role_name {
  type = string
}