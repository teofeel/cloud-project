variable "main_vpc_cidr_block" {
  type    = string
  default = "10.0.0.0/16"
}

variable "main_vpc_instance_tenancy" {
  type    = string
  default = "default"
}

variable "public_subnet_cidr_block" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr_block" {
  type    = string
  default = "10.0.2.0/24"
}

variable "public_subnet_map_on_launch" {
  type    = bool
  default = true
}

variable "route_table_cidr_block" {
  type    = string
  default = "0.0.0.0/0"
}

variable "nat_sg_ingress_from_port" {
  type = number
}

variable "nat_sg_ingress_to_port" {
  type = number
}

variable "nat_sg_ingress_protocol" {
  type = string
}


variable "nat_ec2_instance_name" {
  type = string
}

variable "nat_ec2_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "nat_sg_name" {
  type = string
}

variable "collectors_sg_name" {
  type = string
}

variable "collectors_sg_egress_from_port" {
  type    = number
  default = 443
}

variable "collectors_sg_egress_to_port" {
  type    = number
  default = 443
}

variable "collectors_sg_egress_protocol" {
  type    = string
  default = "tcp"
}

variable "internet_cidr_block" {
  type    = string
  default = "0.0.0.0/0"
}

variable "s3_bronze_bucket_name" {
  type = string
}

variable "s3_silver_bucket_name" {
  type = string
}

variable "hacker_news_lambda_name" {
  type = string
}

variable "hn_source_file_path" {
  type = string
}

variable "hn_output_zip_path" {
  type = string
}

variable "hn_handler" {
  type = string
}

variable "twt_handler" {
  type = string
}

variable "twt_lambda_name" {
  type = string
}

variable "twt_source_file_path" {
  type = string
}

variable "twt_output_zip_path" {
  type = string
}

variable "normalize_hn_lambda_handler" {
  type = string
}

variable "normalize_hn_lambda_name" {
  type = string
}

variable "normalize_hn_source_file_path" {
  type = string
}

variable "normalize_hn_output_zip_path" {
  type = string
}


variable "discord_notification_lambda_name" {
  type = string
}

variable "discord_notification_lambda_handler" {
  type = string
}

variable "discord_notification_file_path" {
  type = string
}

variable "discord_notification_zip_path" {
  type = string
}

variable "discord_webhook_url" {
  type = string
}

variable "discord_failure_notification_rule_name" {
  type = string
}

variable "kaggle_username" {
  type        = string
  sensitive   = true
}

variable "kaggle_key" {
  type        = string
  sensitive   = true
}