resource "aws_vpc" "main_vpc" {
  cidr_block       = var.main_vpc_cidr_block
  instance_tenancy = var.main_vpc_instance_tenancy
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.public_subnet_cidr_block
  map_public_ip_on_launch = var.subnet_map_on_launch
}

resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.private_subnet_cidr_block
  map_public_ip_on_launch = false
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id

  route {
    cidr_block = var.route_table_cidr_block
    gateway_id = aws_internet_gateway.internet_gateway.id
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_route_table_association" "table_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

resource "aws_route_table_association" "private_table_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id = aws_vpc.main_vpc.id
  service_name = "com.amazonaws.eu-west-1.s3"

  vpc_endpoint_type = "Gateway"

  tags = {
    Name = "s3-gateway-endpoint"
  }
}

resource "aws_vpc_endpoint_route_table_association" "private_s3" {
  vpc_endpoint_id = aws_vpc_endpoint.s3.id
  route_table_id = aws_route_table.private_route_table.id
}