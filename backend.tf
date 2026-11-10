terraform {
  backend "s3" {
    bucket       = "terraform-em-producao-tfstate-907079643427"
    key          = "atlantis/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    kms_key_id   = "alias/terraform-state"
    use_lockfile = true
  }
}
