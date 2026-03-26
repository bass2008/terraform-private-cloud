output "network_id" {
  description = "ID of the created VPC network"
  value       = yandex_vpc_network.this.id
}

output "subnet_ids" {
  description = "Map of subnet IDs keyed by zone"
  value = {
    for _, subnet in yandex_vpc_subnet.this : subnet.zone => subnet.id
  }
}
