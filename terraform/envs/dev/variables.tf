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

