# One resource owns the complete policy, including any public-read exception.
resource "aws_s3_bucket_policy" "this" {
  count  = var.access_policy == "unmanaged" ? 0 : 1
  bucket = stackit_objectstorage_bucket.this.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [merge({
        Sid          = "DenyOtherCredentialGroups"
        Effect       = "Deny"
        NotPrincipal = { AWS = stackit_objectstorage_credentials_group.this.urn }
        Resource     = ["arn:aws:s3:::${stackit_objectstorage_bucket.this.name}", "arn:aws:s3:::${stackit_objectstorage_bucket.this.name}/*"]
      }, var.access_policy == "public-read" ? { NotAction = "s3:GetObject" } : { Action = "s3:*" })],
      var.access_policy == "public-read" ? [{
        Sid       = "AllowPublicRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::${stackit_objectstorage_bucket.this.name}/*"
      }] : []
    )
  })
}
