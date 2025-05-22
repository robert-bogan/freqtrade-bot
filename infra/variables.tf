variable "hcloud_token" {
  description = "Hetzner API token"
  type        = string
  sensitive   = true
}

variable "ssh_key_name" {
  description = "SSH key name in Hetzner Cloud"
  type        = string
}

variable "client_ip" {
  description = "The IP address allowed to access the server"
  type        = string
  sensitive   = true
}
