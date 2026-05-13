terraform {
  required_providers {
    aws = {
        source = "hashicorp/aws"
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