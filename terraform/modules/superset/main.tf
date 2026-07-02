module "superset_sg" {
  source  = "../security_groups"
  sg_name = "superset-access"

  vpc_id = var.vpc_id

  ingress_rules = [
    {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      from_port   = 8088
      to_port     = 8088
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      from_port = 5432
      to_port = 5432
      protocol = "tcp"
      cidr_blocks = var.injector_cidr_blocks
    }
  ]
}

resource "aws_key_pair" "deployer" {
  key_name   = "cloud_projekat"
  public_key = file("${path.module}/scripts/cloud_projekat.pub")
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 6.0"

  name          = "visualization-instance"
  instance_type = "t3.micro"
  monitoring    = true

  subnet_id              = var.vpc_public_subnet_id
  vpc_security_group_ids = [module.superset_sg.sg_id]
  key_name               = "cloud_projekat"


  user_data_replace_on_change = true
  user_data = templatefile("${path.module}/scripts/deploy_script.sh", {
    DB_PASSWORD = var.db_password,
    DDL_SCHEMA  = file("${path.module}/scripts/cloud-ddl.sql")
  })


}