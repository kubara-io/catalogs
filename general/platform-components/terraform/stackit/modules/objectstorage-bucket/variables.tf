variable "project_id" {
  description = "STACKIT Project ID to associate all ObjectStorage resources with"
  type        = string
}

variable "credentials_group_name" {
  description = "Display name for the ObjectStorage credentials group"
  type        = string
}

variable "bucket_name" {
  description = "DNS-compatible name for the ObjectStorage bucket"
  type        = string
}

variable "region" {
  description = "Region for all resources; defaults to provider region if unset"
  type        = string
  default     = "eu01"
}

variable "access_policy" {
  description = "Bucket policy mode: unmanaged preserves existing policy ownership, private restricts all access to this credential group, public-read additionally allows anonymous object downloads."
  type        = string
  default     = "unmanaged"
  nullable    = false

  validation {
    condition     = contains(["unmanaged", "private", "public-read"], var.access_policy)
    error_message = "access_policy must be unmanaged, private, or public-read."
  }
}
