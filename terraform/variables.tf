variable "hcloud_token" {
  description = "Hetzner Cloud API Token"
  type        = string
  sensitive   = true
}

variable "admin_keys" {
  description = "Map of machine names to their public SSH keys"
  type        = map(string)
}

variable "servers" {
  description = "Map of servers to create"
  type = map(object({
    server_type = string
    private_ip  = string
  }))
}

variable "storage_boxes" {
  description = "Map of storage boxes to create"
  type = map(object({
    location         = string
    storage_box_type = string
  }))
}

variable "storage_box_secrets" {
  description = "Map of storage box names to their passwords"
  type        = map(string)
  sensitive   = true
}

variable "storage_box_subaccounts" {
  description = "Map of subaccounts to create"
  type = map(object({
    storage_box_id = string
    home_directory = string
    description    = string
  }))
}

variable "storage_box_subaccount_secrets" {
  description = "Map of subaccount names to their passwords"
  type        = map(map(string))
  sensitive   = true
}
