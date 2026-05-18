output "vpc_id" {
  description = "ID of VPC"
  value       = aws_vpc.main_vpc.id
}

output "subnet_id" {
  description = "ID of subnet"
  value       = aws_subnet.main_subnet.id
}

output "vpc_arn" {
  description = "ARN of VPC"
  value       = aws_vpc.main_vpc.arn
}

output "subnet_arn" {
  description = "ARN of subnet"
  value       = aws_subnet.main_subnet.arn
}

output "igw_id" {
  description = "ID of internet gateway"
  value       = aws_internet_gateway.internet_gateway.id
}

output "route_table_id" {
  description = "ID of route table"
  value       = aws_route_table.route_table.id
}