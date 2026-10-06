terraform {
  required_version = ">= 1.11.0"
  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = "0.117.0"
    }
    time = {
      source  = "hashicorp/time"
      version = "0.14.2"
    }
  }
}
