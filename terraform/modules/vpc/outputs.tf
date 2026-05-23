output "vpc_id" {
  description = "ID of VPC"
  value       = aws_vpc.main_vpc.id
}

output "public_subnet_id" {
  description = "ID of subnet"
  value       = aws_subnet.public_subnet.id
}

output "private_subnet_id" {
  description = "ID of private subnet"
  value       = aws_subnet.private_subnet.id
}
output "vpc_arn" {
  description = "ARN of VPC"
  value       = aws_vpc.main_vpc.arn
}

output "public_subnet_arn" {
  description = "ARN of subnet"
  value       = aws_subnet.public_subnet.arn
}

output "public_subnet_cidr" {
  description = "CIDR block of public subnet"
  value       = aws_subnet.public_subnet.cidr_block
}

output "private_subnet_arn" {
  description = "ARN of private subnet"
  value       = aws_subnet.private_subnet.arn
}

output "private_subnet_cidr" {
  description = "CIDR block of public subnet"
  value       = aws_subnet.private_subnet.cidr_block
}

output "igw_id" {
  description = "ID of internet gateway"
  value       = aws_internet_gateway.internet_gateway.id
}

output "route_table_id" {
  description = "ID of route table"
  value       = aws_route_table.public_route_table.id
}

output "private_route_table_id" {
  description = "ID of private route table"
  value       = aws_route_table.private_route_table.id
}