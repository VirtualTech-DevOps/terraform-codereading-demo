# https://developer.hashicorp.com/terraform/language/expressions/version-constraints
terraform {
  required_version = "~> 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.29.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.1"
    }
  }
}
