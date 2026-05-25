variable "network_name" {
  type        = string
  description = "Name of VPC network"
}

variable "network_description" {
  type        = string
  description = "Description of VPC network"
  default     = "Managed network for private cloud"
}

variable "subnets" {
  type = map(object({
    name        = string
    description = string
    zone        = string
    cidr        = string
  }))
  description = "Map of subnets to create"
}
