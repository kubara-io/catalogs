terraform {
  required_version = ">= 1.9.3"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "< 4.0.0"
    }
  }
}
