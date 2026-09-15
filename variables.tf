variable "project_name" {
  description = "Nom logique du projet"
  type        = string
  default     = "edunova"
}
variable "environment" {
  description = "Environnement cible"
  type        = string
  default     = "staging"
}
variable "aws_region" {
  type    = string
  default = "eu-west-3"
}
variable "vpc_cidr" {
  type    = string
  default = "10.30.0.0/16"
}

# Ajout des 4 subnets
variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.1.0/24", "10.30.2.0/24"]
}
variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.30.11.0/24", "10.30.12.0/24"]
}