variable "vpc_id" {
  type = string
}

variable "vpc_public_subnet_id" {
  type = string
}

variable "db_password" {
  type = string
}

variable "injector_cidr_blocks"{
  type = list(string)
}