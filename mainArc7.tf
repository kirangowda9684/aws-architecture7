terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region  = "eu-central-1"
  profile = "845093662705_Adv-Type6"
}

#VPC
resource "aws_vpc" "first-vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "Architecture7"
  }
}

#Internet Gateway
resource "aws_internet_gateway" "IG" {
  vpc_id = aws_vpc.first-vpc.id

  tags = {
    Name = "Internet Gateway"
  }
}

#Nat Gateway
resource "aws_nat_gateway" "NG" {
  allocation_id = aws_eip.teip.id
  subnet_id     = aws_subnet.subnet1-ec21.id

  tags = {
    Name = "NAT Gateway"
  }
  depends_on = [aws_internet_gateway.IG]

}
resource "aws_eip" "teip" {
  vpc = true

}
#Public Route Table
resource "aws_route_table" "public-RT" {
  vpc_id = aws_vpc.first-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IG.id
  }

  tags = {
    Name = "Public Route table"
  }
}

resource "aws_route_table_association" "public-RT-Asso" {
  subnet_id      = aws_subnet.subnet1-ec21.id
  route_table_id = aws_route_table.public-RT.id
}

#Private Route Table
resource "aws_route_table" "pri-RT" {
  vpc_id = aws_vpc.first-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.NG.id
  }


  tags = {
    Name = "Private Route table"
  }
}

resource "aws_route_table_association" "pri-RT-Asso" {
  subnet_id      = aws_subnet.subnet2-rds1.id
  route_table_id = aws_route_table.pri-RT.id
}
#Subnet for ec2
resource "aws_subnet" "subnet1-ec21" {
  vpc_id            = aws_vpc.first-vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "vpc-public1"
  }
}

resource "aws_subnet" "subnet1-ec212" {
  vpc_id            = aws_vpc.first-vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "vpc-public2"
  }
}
#Subnet for rds
resource "aws_subnet" "subnet2-rds1" {
  vpc_id            = aws_vpc.first-vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "eu-central-1a"
  tags = {
    Name = "rds-private1"
  }
}
resource "aws_subnet" "subnet2-rds2" {
  vpc_id            = aws_vpc.first-vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "eu-central-1b"
  tags = {
    Name = "rds-private2"
  }
}
#Auto Scaling
data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base*"]
  }

}

resource "tls_private_key" "RSA-KEY" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "TF-KEY" {
  content  = tls_private_key.RSA-KEY.private_key_pem
  filename = "TF-KEY"
}

resource "aws_key_pair" "TFKEY" {
  key_name   = "TFKEY"
  public_key = tls_private_key.RSA-KEY.public_key_openssh
}
resource "aws_launch_configuration" "Launch_config" {
  name          = "Launch_config"
  image_id      = data.aws_ami.windows.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.TFKEY.key_name

  lifecycle {
    create_before_destroy = true
  }
}
resource "aws_autoscaling_group" "asg" {
  name                      = "asg"
  launch_configuration      = aws_launch_configuration.Launch_config.name
  min_size                  = 1
  max_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  vpc_zone_identifier       = [aws_subnet.subnet1-ec21.id]

  lifecycle {
    create_before_destroy = true
  }
}

#Public security group
resource "aws_security_group" "public_sg" {
  name        = "public_sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = aws_vpc.first-vpc.id

  ingress {
    description = "TLS from VPC"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TLS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "TLS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "public security group"
  }
}
#Elastic Load Balancer
resource "aws_lb" "vpc_lb" {
  name                       = "vpclb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.public_sg.id]
  subnets                    = [aws_subnet.subnet1-ec21.id, aws_subnet.subnet1-ec212.id]
  enable_deletion_protection = false
}

#Private security group
resource "aws_security_group" "private_sg" {
  name        = "private_sg"
  description = "Allow TLS inbound traffic from public subnet"
  vpc_id      = aws_vpc.first-vpc.id

  ingress {
    description = "TLS from VPC"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["10.0.1.0/24"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "private security group"
  }
}
#RDS
resource "aws_db_instance" "rds_db" {
  identifier             = "mysql-db-02"
  allocated_storage      = 5
  availability_zone      = "eu-central-1a"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.private_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.db-sub-grp.name
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t2.micro"
  name                   = "rds_db"
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.mysql5.7"
  skip_final_snapshot    = true


  tags = {
    Name = "DBSERVER"
  }
}
resource "aws_db_snapshot" "testdbsnap" {
  db_instance_identifier = aws_db_instance.rds_db.id
  db_snapshot_identifier = "testsnapshot01"
}
resource "aws_db_subnet_group" "db-sub-grp" {
  name       = "db-sub-grp"
  subnet_ids = [aws_subnet.subnet2-rds1.id, aws_subnet.subnet2-rds2.id]

  tags = {
    Name = "My DB subnet group"
  }
}
/*
#S3 bucket
resource "aws_s3_bucket" "backup-bucket" {
  bucket = "backup-bucket-terraform-architecture7"
  tags = {
    Name = "kiran-backup-bucket"

  }
}

#Access control list for s3
resource "aws_s3_bucket_acl" "s3bucketacl" {
  bucket = aws_s3_bucket.backup-bucket.id
  acl    = "private"
}
*/