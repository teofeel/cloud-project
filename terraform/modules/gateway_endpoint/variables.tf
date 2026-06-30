variable "vpc_id" {
  type = string
}

variable "service_name" {
  type = string
}

variable "endpoint_type" {
  type = string
}

variable "private_route_table_ids" {
  type    = set(string)
  default = []
}

variable "private_subnet_ids" {
  type    = list(string)
  default = []
}

variable "security_group_ids" {
  type    = list(string)
  default = []
}

variable "private_dns_enabled" {
  type    = bool
  default = true
}