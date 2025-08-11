// Terraform configuration for Hetzner Cloud (moved from repo root)
terraform {
  cloud {
    organization = "OdbDesign"
    workspaces { name = "cloud-ws" }
  }
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

variable "server_image" {
  description = "ubuntu-24.04"
  type        = string
  default     = "ubuntu-24.04"
}

variable "server_type" {
  description = "Hetzner Cloud server type"
  type        = string
  default     = "cpx31"
}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_server" "raid_server" {
  name        = "raid10-server"
  server_type = var.server_type
  image       = var.server_image
  location    = "nbg1"
  ssh_keys    = ["nam20485@PRECISION5820"]
}

output "server_ip" {
  value = hcloud_server.raid_server.ipv4_address
}

output "server_type" {
  value = hcloud_server.raid_server.server_type
}
