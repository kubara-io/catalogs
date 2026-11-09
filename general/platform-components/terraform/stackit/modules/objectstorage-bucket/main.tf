# 1) Create a credentials group
resource "stackit_objectstorage_credentials_group" "this" {
  project_id = var.project_id
  name       = var.credentials_group_name
  region     = var.region
}

# 2) Create the bucket, only after the group exists
resource "stackit_objectstorage_bucket" "this" {
  project_id = var.project_id
  name       = var.bucket_name
  region     = var.region

  depends_on = [stackit_objectstorage_credentials_group.this]
}

# 3) Create one credential in that group
resource "stackit_objectstorage_credential" "this" {
  project_id           = var.project_id
  credentials_group_id = stackit_objectstorage_credentials_group.this.credentials_group_id
  region               = var.region

  depends_on = [stackit_objectstorage_credentials_group.this]
}
