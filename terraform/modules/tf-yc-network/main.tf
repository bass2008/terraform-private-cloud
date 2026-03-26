resource "yandex_vpc_network" "this" {
  name        = var.network_name
  description = var.network_description
}

resource "yandex_vpc_subnet" "this" {
  for_each = var.subnets

  name           = each.value.name
  description    = each.value.description
  zone           = each.value.zone
  network_id     = yandex_vpc_network.this.id
  v4_cidr_blocks = [each.value.cidr]
}
