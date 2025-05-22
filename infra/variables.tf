variable "hcloud_token" {
  description = "Hetzner API token"
  type        = string
  default     = var.hcloud_token
  sensitive   = true
}

variable "ssh_key_name" {
  description = "SSH key name in Hetzner Cloud"
  default     = var.ssh_key_name
  type        = string
}

variable "client_ip" {
  description = "The IP address allowed to access the server"
  type        = string
  default     = var.client_ip
  sensitive   = true
}
