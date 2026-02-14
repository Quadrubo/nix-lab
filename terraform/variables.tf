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
