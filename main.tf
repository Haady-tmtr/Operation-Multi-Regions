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