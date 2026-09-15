resource "aws_vpc" "main" {
  cidr_block           = "10.30.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name      = "edunova-vpc"
    Project   = "operation-multi-regions"
    ManagedBy = "Terraform"
  }
}