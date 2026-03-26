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

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for VM access"
}

variable "vm_name" {
  type        = string
  description = "Name of the virtual machine"
  default     = "personal-vm"
}

variable "image_id" {
  type        = string
  description = "Boot disk image ID (Ubuntu 22.04 LTS)"
  default     = "fd8prsl2cdb6cpt4fkgs"
}

variable "network_name" {
  type        = string
  description = "Name of VPC network"
  default     = "personal-network"
}

variable "network_description" {
  type        = string
  description = "Description of VPC network"
  default     = "VPC network for personal VM"
}

variable "subnets" {
  type = map(object({
    name        = string
    description = string
    zone        = string
    cidr        = string
  }))
  description = "Map of subnets to create"
  default = {
    ru-central1-a = {
      name        = "personal-subnet-a"
      description = "Subnet in ru-central1-a"
      zone        = "ru-central1-a"
      cidr        = "10.10.0.0/24"
    }
  }
}
