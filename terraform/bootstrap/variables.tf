variable "yc_token" {
  type        = string
  description = "Yandex Cloud IAM token"
  sensitive   = true
}

variable "yc_cloud_id" {
  type        = string
  description = "Yandex Cloud cloud id"
}

variable "yc_folder_id" {
  type        = string
  description = "Yandex Cloud folder id"
}

variable "yc_zone" {
  type        = string
  description = "Default availability zone"
  default     = "ru-central1-a"
}

variable "tf_state_bucket_name" {
  type        = string
  description = "Name of the Object Storage bucket for Terraform state"
  default     = "private-cloud-tfstate-hjb4rfs"
}

variable "static_bucket_name" {
  type        = string
  description = "Name of the Object Storage bucket for static files"
  default     = "private-cloud-static-hjb4rfs"
}

variable "tf_state_sa_name" {
  type        = string
  description = "Service account name for Terraform state bucket access"
  default     = "private-cloud-terraform-state-sa"
}
