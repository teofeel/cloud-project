terraform {
  required_providers {
    aws = {
        source = "hashi/corp"
        version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-west-1"
}

# here we are creating VPC and lambda, S3 services using created modules from them