terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }

  backend "s3" {
    bucket = "nix-lab-state"
    key    = "terraform.tfstate"
    region = "auto"

    endpoints = {
      s3 = "https://211457751bed8daf946c0444f3c3d47c.r2.cloudflarestorage.com"
    }

    # Required for R2 compatibility
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
    use_path_style              = true
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

# --- Networking ---
resource "hcloud_network" "private_network" {
  name     = "private-network"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "default_private_network_subnet" {
  type         = "cloud"
  network_id   = hcloud_network.private_network.id
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

# --- SSH Keys ---
resource "hcloud_ssh_key" "admins" {
  for_each   = var.admin_keys
  name       = each.key
  public_key = each.value
}

# --- Servers ---
resource "hcloud_server" "machines" {
  for_each = var.servers

  name        = each.key
  server_type = each.value.server_type
  image       = "debian-12"
  location    = "nbg1" # Nuremburg

  network {
    network_id = hcloud_network.private_network.id
    ip         = each.value.private_ip
  }

  ssh_keys = [for k in hcloud_ssh_key.admins : k.id]
}

output "server_ips" {
  value = {
    # map: "publy" => "46.x.x.x"
    for name, server in hcloud_server.machines : name => server.ipv4_address
  }
}
