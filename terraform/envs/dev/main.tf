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
  main_subnet_cidr_block    = var.main_subnet_cidr_block
  main_subnet_map_on_launch = var.main_subnet_map_on_launch
  route_table_cidr_block    = var.route_table_cidr_block
}