terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.60"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = ">= 5"
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

provider "cloudflare" {
  api_token = var.cloudflare_api_token
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

# --- Storage Boxes ---
resource "hcloud_storage_box" "boxes" {
  for_each = var.storage_boxes

  name             = each.key
  location         = each.value.location
  storage_box_type = each.value.storage_box_type
  password         = var.storage_box_secrets[each.key]

  access_settings = {
    reachable_externally = true
    ssh_enabled          = true
  }
}

resource "hcloud_storage_box_subaccount" "subaccounts" {
  for_each = var.storage_box_subaccounts

  storage_box_id = hcloud_storage_box.boxes[each.value.storage_box_id].id
  description    = each.value.description

  home_directory = each.value.home_directory
  password       = var.storage_box_subaccount_secrets[each.value.storage_box_id][each.key]

  access_settings = {
    reachable_externally = true
    ssh_enabled          = true
  }
}

# --- DNS Records ---
locals {
  server_ips = {
    for name, server in hcloud_server.machines : name => server.ipv4_address
  }
}

locals {
  dns_records_flat = flatten([
    for domain_key, domain_data in var.domains : [
      for record in domain_data.records : {
        unique_id = "${domain_key}-${record.name}-${record.type}-${md5(record.content != null ? record.content : (record.server_name != null ? record.server_name : ""))}"

        zone_id     = domain_data.zone_id
        name        = record.name
        type        = record.type
        content     = record.content
        server_name = record.server_name
        ttl         = record.ttl
        proxied     = record.proxied
        priority    = record.priority
      }
    ]
  ])
}

resource "cloudflare_dns_record" "this" {
  for_each = {
    for record in local.dns_records_flat : record.unique_id => record
  }

  zone_id = each.value.zone_id
  type    = each.value.type
  name    = each.value.name
  content = (
    each.value.server_name != null ?
    hcloud_server.machines[each.value.server_name].ipv4_address :
    each.value.content
  )
  ttl      = each.value.ttl
  proxied  = each.value.proxied
  priority = each.value.priority
}
