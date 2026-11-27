mock_provider "stackit" {
  mock_resource "stackit_objectstorage_credentials_group" {
    defaults = {
      credentials_group_id = "00000000-0000-0000-0000-000000000001"
      urn                  = "urn:sgws:identity::12345678901234567890:group/credentials-group-example"
    }
  }
}

mock_provider "aws" {}

variables {
  project_id             = "00000000-0000-0000-0000-000000000000"
  bucket_name            = "example-backup"
  credentials_group_name = "example-backup"
}

run "preserve_existing_policy_ownership" {
  command = apply

  assert {
    condition     = length(aws_s3_bucket_policy.this) == 0
    error_message = "The default must not create or take ownership of a bucket policy."
  }
}

run "isolate_private_bucket" {
  command = apply
  variables {
    access_policy = "private"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this[0].policy) == {
      Version = "2012-10-17"
      Statement = [{
        Sid          = "DenyOtherCredentialGroups"
        Effect       = "Deny"
        NotPrincipal = { AWS = "urn:sgws:identity::12345678901234567890:group/credentials-group-example" }
        Action       = "s3:*"
        Resource     = ["arn:aws:s3:::example-backup", "arn:aws:s3:::example-backup/*"]
      }]
    }
    error_message = "Private buckets must deny every S3 action on the bucket and objects except for their own group."
  }
}

run "allow_only_public_downloads" {
  command = apply
  variables {
    access_policy = "public-read"
  }

  assert {
    condition = jsondecode(aws_s3_bucket_policy.this[0].policy) == {
      Version = "2012-10-17"
      Statement = [
        {
          Sid          = "DenyOtherCredentialGroups"
          Effect       = "Deny"
          NotPrincipal = { AWS = "urn:sgws:identity::12345678901234567890:group/credentials-group-example" }
          NotAction    = "s3:GetObject"
          Resource     = ["arn:aws:s3:::example-backup", "arn:aws:s3:::example-backup/*"]
        },
        {
          Sid       = "AllowPublicRead"
          Effect    = "Allow"
          Principal = "*"
          Action    = "s3:GetObject"
          Resource  = "arn:aws:s3:::example-backup/*"
        }
      ]
    }
    error_message = "Public reads must be the only exception to group isolation, in the same policy document."
  }
}

run "reject_unknown_access_mode" {
  command = plan
  variables {
    access_policy = "public-write"
  }
  expect_failures = [var.access_policy]
}
