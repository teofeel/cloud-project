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
  type = string
  default = "10.0.2.0/24"
}

variable "subnet_map_on_launch" {
  type    = bool
  default = true
}

variable "route_table_cidr_block" {
  type    = string
  default = "0.0.0.0/0"
}