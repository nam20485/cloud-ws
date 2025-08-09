terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.0"
    }
  }
}

variable "hcloud_token" {
  description = "Hetzner Cloud API token"
  sensitive   = true
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_server" "raid_server" {
  name        = "raid10-server"
  server_type = "cpx31" // Choose a server type with at least 4 drives available
  image       = var.server_image // Updated to Ubuntu 24.04 (configurable)
  location    = "nbg1"
  ssh_keys    = ["your_ssh_key_name"] // Replace with your SSH key name from Hetzner Cloud
}

// Image variable so we can easily switch Ubuntu versions (e.g. ubuntu-24.04)
variable "server_image" {
  description = "Hetzner Cloud image slug (e.g. ubuntu-24.04, ubuntu-22.04)"
  type        = string
  default     = "ubuntu-24.04"
}

output "server_ip" {
  value = hcloud_server.raid_server.ipv4_address
}
