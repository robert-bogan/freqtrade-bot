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

  users:
    - default
    - name: freqtrade
      groups: [docker, sudo]
      shell: /bin/bash
      sudo: ['ALL=(ALL) NOPASSWD:ALL']
      lock_passwd: true

  packages:
    - git
    - python3-pip
    - docker.io
    - docker-compose
    - gocryptfs
    - tree

  write_files:
    - path: /home/freqtrade/.gocryptfs_pass
      permissions: '0600'
      owner: freqtrade:freqtrade
      content: "${var.gocryptfs_pass}"

  runcmd:
    # Start Docker
    - systemctl enable docker
    - systemctl start docker

    # Create secure directories
    - mkdir -p /mnt/secure_raw
    - mkdir -p /mnt/secure
    - chown freqtrade:freqtrade /mnt/secure_raw /mnt/secure

    # Initialize and mount gocryptfs as freqtrade
    - runuser -l freqtrade -c "gocryptfs -init /mnt/secure_raw || true"
    - runuser -l freqtrade -c "gocryptfs --extpass 'cat /home/freqtrade/.gocryptfs_pass' /mnt/secure_raw /mnt/secure"


    # Render config.json if template exists
    - runuser -l freqtrade -c 'bash -c "
        cd /mnt/secure/freqtrade-bot
        if [ -f config/config.json.template ]; then
          export \$(cat config/.env | xargs)
          envsubst < config/config.json.template > user_data/config.json
        fi
    "'


    - runuser -l freqtrade -c "mkdir -p /mnt/secure/freqtrade-bot/user_data"
    # - chown -R freqtrade:freqtrade /mnt/secure/freqtrade-bot/user_data

    # Set up freqtrade folders
    - runuser -l freqtrade -c "cp /mnt/secure/freqtrade-bot/config/config.json /mnt/secure/freqtrade-bot/user_data/config.json"
    # - runuser -l freqtrade -c "chown -R freqtrade:freqtrade /mnt/secure/freqtrade-bot/user_data"
    # - runuser -l freqtrade -c "chmod 644 /mnt/secure/freqtrade-bot/user_data/config.json"

    # Clone the repo as freqtrade user
    - runuser -l freqtrade -c "git clone https://github.com/robert-bogan/freqtrade-bot.git /mnt/secure/freqtrade-bot"

    # Create env config
    - runuser -l freqtrade -c "mkdir -p /mnt/secure/freqtrade-bot/config"
    - runuser -l freqtrade -c "echo "POSTGRES_PASSWORD=${var.postgres_password}" > /mnt/secure/freqtrade-bot/config/.env"

    # Optional debug
    - ls -la /mnt/secure/freqtrade-bot

    # Docker compose as freqtrade user
    - runuser -l freqtrade -c "cd /mnt/secure/freqtrade-bot && docker-compose down || true"
    - runuser -l freqtrade -c "cd /mnt/secure/freqtrade-bot && docker-compose up -d --build"

    # Clean up secrets
    - rm -f /home/freqtrade/.gocryptfs_pass
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
