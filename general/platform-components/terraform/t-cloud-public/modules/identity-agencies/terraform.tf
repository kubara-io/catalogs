terraform {
  required_version = ">= 1.11.0"

  required_providers {
    opentelekomcloud = {
      source  = "opentelekomcloud/opentelekomcloud"
      version = ">= 1.36.64, < 2.0.0"
    }
  }
}
