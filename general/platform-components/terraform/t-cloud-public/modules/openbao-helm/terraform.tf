terraform {
  required_version = ">= 1.9.3"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "< 4.0.0"
    }
  }
}
