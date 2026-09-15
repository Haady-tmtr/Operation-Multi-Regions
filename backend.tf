terraform {
  backend "s3" {
    bucket       = "goai-tfstate-680319777993"
    key          = "staging/terraform.tfstate"
    region       = "eu-west-3"
    encrypt      = true
    use_lockfile = true

  }
}