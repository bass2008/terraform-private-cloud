module "network" {
  source              = "./modules/tf-yc-network"
  network_name        = var.network_name
  network_description = var.network_description
  subnets             = var.subnets
}

resource "yandex_vpc_address" "static" {
  name = "vm-static-ip"

  external_ipv4_address {
    zone_id = var.yc_zone
  }
}

resource "yandex_compute_instance" "vm" {
  name                      = var.vm_name
  zone                      = var.yc_zone
  platform_id               = "standard-v3"
  hostname                  = var.vm_name
  allow_stopping_for_update = true

  resources {
    cores         = 2
    memory        = 1
    core_fraction = 20
  }

  boot_disk {
    initialize_params {
      image_id = var.image_id
      size     = 10
      type     = "network-hdd"
    }
  }

  scheduling_policy {
    preemptible = false
  }

  network_interface {
    subnet_id      = module.network.subnet_ids[var.yc_zone]
    nat            = true
    nat_ip_address = yandex_vpc_address.static.external_ipv4_address[0].address
  }

  metadata = {
    ssh-keys = "ubuntu:${trimspace(var.ssh_public_key)}"
  }
}

output "vm_external_ip" {
  value = yandex_compute_instance.vm.network_interface[0].nat_ip_address
}

output "vm_internal_ip" {
  value = yandex_compute_instance.vm.network_interface[0].ip_address
}

output "ssh_command" {
  value = "ssh ubuntu@${yandex_compute_instance.vm.network_interface[0].nat_ip_address}"
}
