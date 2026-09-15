terraform {
  backend "s3" {}
  required_providers {
    aws = { source = "hashicorp/aws" }
  }

}
provider "aws" {
  region = var.aws_region
}
variable "aws_region" { type = string }
variable "vpc_cidr" { type = string }

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}
module "platform" {
  source               = "../../modules/platform"
  project_name         = "edunova"
  environment          = "staging"
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}
