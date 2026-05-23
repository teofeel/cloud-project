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

  update_route_tables = true
  route_tables_ids = {
    "private-routing" = module.aws_vpc.private_route_table_id
  }

  instance_type                 = var.nat_ec2_instance_type
  additional_security_group_ids = [module.nat_sg.sg_id]
}

# create sg for collectors lambda that will send req to tw and hn
module "collectors_sg" {
  source  = "../../modules/security_groups"
  sg_name = var.collectors_sg_name
  vpc_id  = module.aws_vpc.vpc_id

  ingress_rules = []

  egress_rules = [{
    from_port   = var.collectors_sg_egress_from_port
    to_port     = var.collectors_sg_egress_to_port
    protocol    = var.collectors_sg_egress_protocol
    cidr_blocks = [var.internet_cidr_block]
  }]
}