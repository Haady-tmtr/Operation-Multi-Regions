data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name          = "${var.project_name}-${var.environment}-vpc"
    Project       = var.project_name
    ManagedBy     = "Terraform"
    Environnement = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = 2 ## crée cette ressource 2 fois, donc ce qui sera crée sont:  aws_subnet.public[0], aws_subnet.public[1]
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index] # repartition des ressources sur plusieurs AZ pour améliorer la disponibilité.
  map_public_ip_on_launch = true                                                     # EC2 -> public subnet -> Les instances lancées ici peuvent recevoir automatiquement une IP publique.
  tags = {
    Name        = "${var.project_name}-${var.environment}-public-${count.index + 1}"
    Environment = var.environment
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]
  tags = {
    Name        = "${var.project_name}-${var.environment}-private-${count.index + 1}"
    Environment = var.environment
  }
}

## Internet gatway and public table
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-${var.environment}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-${var.environment}-rt-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


## Security group
resource "aws_security_group" "web" {
  name        = "${var.project_name}-${var.environment}-web-sg"
  description = "HTTP/HTTPS public"
  vpc_id      = aws_vpc.main.id

  ingress { ## traffic entrant : Autoriser le port TCP 80
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress { ## traffic entrant dans la ressource : Autoriser le port TCP 443
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] ## Toutes les adresses IPv4
  }
  egress { ## traffic sortant
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] ## Toutes les destinations IPv4
  }
}


## S3 Bucket
data "aws_caller_identity" "current" {}
resource "aws_s3_bucket" "assets" {
  bucket = "${var.project_name}-${var.environment}-assets-${var.aws_region}-${data.aws_caller_identity.current.account_id}" # j'ai rajouté -${var.aws_region} pour rendre différent selon la région, sinon erreur 
}
resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}





## IAM EC2 role

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }

}
resource "aws_iam_role" "ec2" {
  name               = "${var.project_name}-${var.environment}-${var.aws_region}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-${var.environment}-${var.aws_region}-ec2-profile"
  role = aws_iam_role.ec2.name
}

## Ajout d'un accès ciblé au bucket et SessionManager : on attachera AmazonSSMManagedInstanceCore au rôle
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

### Trouver dynamiquement l'AMI Amazon Linux
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

### Création de l'instance EC2
resource "aws_instance" "web" {
  ami                    = data.aws_ssm_parameter.al2023.value
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y nginx
    echo "<h1>${var.project_name} - ${var.environment}</h1>" > /usr/share/nginx/html/index.html
    systemctl enable --now nginx
    EOF

  metadata_options {
    http_tokens = "required"
  }
  tags = { Name = "${var.project_name}-${var.environment}-web-01" }
}