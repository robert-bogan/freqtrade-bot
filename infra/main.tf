terraform {
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.32.1"
    }
  }
}


provider "hcloud" {
  token = var.hcloud_token
}

resource "random_id" "suffix" {
  byte_length = 4
}


resource "hcloud_ssh_key" "default" {
  name       = "freqtrade-key-${random_id.suffix.hex}" 
  public_key = file(var.ssh_public_key_path)
}

resource "hcloud_server" "freqtrade" {
  name        = "freqtrade-${random_id.suffix.hex}"
  image       = "ubuntu-22.04"
  server_type = "cpx21"
  location    = "fsn1"
  ssh_keys    = [hcloud_ssh_key.default.id] 

  labels = {
    project = "freqtrade"
  }

user_data = <<-EOF
  #cloud-config
  package_update: true
  package_upgrade: true
  ssh_pwauth: false
  disable_root: false

  packages:
    - git
    - python3-pip
    - docker.io
    - docker-compose
    - gocryptfs
    - tree

  write_files:
    - path: /root/gocryptfs_pass
      permissions: '0600'
      owner: root:root
      content: "${var.gocryptfs_pass}"

  runcmd:
    - systemctl enable docker
    - systemctl start docker

    # Set up secure storage
    - mkdir -p /mnt/secure_raw
    - echo "${var.gocryptfs_pass}" | gocryptfs -init /mnt/secure_raw
    - echo "${var.gocryptfs_pass}" | gocryptfs /mnt/secure_raw /mnt/secure

    # Create required directories
    - mkdir -p /mnt/secure/freqtrade-bot/config
    - chown -R root:root /mnt/secure/freqtrade-bot

    # Docker permissions for root (optional if already root user)
    - usermod -aG docker root

    # Clean up secrets
    - rm -f /root/gocryptfs_pass

  write_files:
    - path: /mnt/secure/freqtrade-bot/config/.env
      permissions: '0600'
      owner: root:root
      content: |
        POSTGRES_PASSWORD=${var.postgres_password}

  runcmd:
    - ls -la config/.env
    - systemctl start docker
    - |     
        # Render the final config.json
        if [ -f config/config.json.template ]; then
          export $(cat config/.env | xargs)
          envsubst < config/config.json.template > user_data/config.json
        fi

        docker compose down
        docker compose up -d --build

EOF

}

resource "hcloud_firewall" "freqtrade_fw" {
  name = "freqtrade-fw-${random_id.suffix.hex}"

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "22"
    source_ips  = ["0.0.0.0/0"]
    description = "Allow SSH"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "8080"
    source_ips  = ["0.0.0.0/0"]
    description = "Freqtrade Web UI"
  }

  rule {
    direction   = "in"
    protocol    = "tcp"
    port        = "5432"
    source_ips  = [var.client_ip]
    description = "PostgreSQL access (optional)"
  }
}

resource "hcloud_firewall_attachment" "fw_attach" {
  firewall_id = hcloud_firewall.freqtrade_fw.id
  server_ids  = [hcloud_server.freqtrade.id]
}


output "server_ip" {
  value = hcloud_server.freqtrade.ipv4_address
}
