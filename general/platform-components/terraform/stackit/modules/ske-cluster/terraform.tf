terraform {
  required_version = ">= 1.11.0"
  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = "0.117.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.9.1"
    }
  }
}
