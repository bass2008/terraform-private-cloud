provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}

resource "yandex_iam_service_account" "terraform_state" {
  name        = var.tf_state_sa_name
  description = "Service account for Terraform state in Object Storage"
}

resource "yandex_resourcemanager_folder_iam_member" "terraform_state_storage" {
  folder_id = var.yc_folder_id
  role      = "storage.admin"
  member    = "serviceAccount:${yandex_iam_service_account.terraform_state.id}"
}

resource "yandex_iam_service_account_static_access_key" "terraform_state" {
  service_account_id = yandex_iam_service_account.terraform_state.id
  description        = "Static access key for Terraform state bucket"
}

resource "yandex_storage_bucket" "terraform_state" {
  bucket        = var.tf_state_bucket_name
  access_key    = yandex_iam_service_account_static_access_key.terraform_state.access_key
  secret_key    = yandex_iam_service_account_static_access_key.terraform_state.secret_key
  force_destroy = true

  versioning {
    enabled = true
  }

  depends_on = [yandex_resourcemanager_folder_iam_member.terraform_state_storage]
}

resource "yandex_storage_bucket" "static" {
  bucket        = var.static_bucket_name
  access_key    = yandex_iam_service_account_static_access_key.terraform_state.access_key
  secret_key    = yandex_iam_service_account_static_access_key.terraform_state.secret_key
  force_destroy = true

  anonymous_access_flags {
    read        = true
    list        = false
    config_read = false
  }

  depends_on = [yandex_resourcemanager_folder_iam_member.terraform_state_storage]
}

output "static_bucket_name" {
  value = yandex_storage_bucket.static.bucket
}

output "static_bucket_domain" {
  value = yandex_storage_bucket.static.bucket_domain_name
}

output "tf_state_bucket_name" {
  value = yandex_storage_bucket.terraform_state.bucket
}

output "tf_state_access_key" {
  value     = yandex_iam_service_account_static_access_key.terraform_state.access_key
  sensitive = true
}

output "tf_state_secret_key" {
  value     = yandex_iam_service_account_static_access_key.terraform_state.secret_key
  sensitive = true
}
