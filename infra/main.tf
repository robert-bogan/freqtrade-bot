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
    - gettext-base   # for envsubst

  write_files:
    - path: /home/freqtrade/.gocryptfs_pass
      permissions: '0600'
      owner: freqtrade:freqtrade
      content: "${var.gocryptfs_pass}"

  runcmd:
    # Ensure docker is enabled and running
    - systemctl enable docker
    - systemctl start docker

    # Create secure mount points
    - mkdir -p /mnt/secure_raw /mnt/secure
    - chown freqtrade:freqtrade /mnt/secure_raw /mnt/secure

    # Initialize gocryptfs if needed
    - runuser -l freqtrade -c "gocryptfs -init /mnt/secure_raw || true"

    # Mount encrypted directory as freqtrade
    - runuser -l freqtrade -c "gocryptfs --extpass 'cat /home/freqtrade/.gocryptfs_pass' /mnt/secure_raw /mnt/secure"

    # Remove any root-owned files in /mnt/secure
    - chown -R freqtrade:freqtrade /mnt/secure

    # Clone bot repo if not exists
    - runuser -l freqtrade -c "if [ ! -d /mnt/secure/freqtrade-bot ]; then git clone https://github.com/robert-bogan/freqtrade-bot.git /mnt/secure/freqtrade-bot; fi"

    # Create config directory and env file
    - runuser -l freqtrade -c "mkdir -p /mnt/secure/freqtrade-bot/config"
    - runuser -l freqtrade -c "echo POSTGRES_PASSWORD=${var.postgres_password} > /mnt/secure/freqtrade-bot/config/.env"

    # Render config.json if template exists
    - runuser -l freqtrade -c "cd /mnt/secure/freqtrade-bot && if [ -f config/config.json.template ]; then export \$(cat config/.env | xargs) && envsubst < config/config.json.template > config/config.json; fi"

    # Ensure user_data dir exists and copy config
    - runuser -l freqtrade -c "mkdir -p /mnt/secure/freqtrade-bot/user_data"
    - runuser -l freqtrade -c "cp /mnt/secure/freqtrade-bot/config/config.json /mnt/secure/freqtrade-bot/user_data/config.json"
    - runuser -l freqtrade -c "chmod 644 /mnt/secure/freqtrade-bot/user_data/config.json"

    # Wait for encrypted mount to be ready before starting docker-compose
    - |
      echo "Waiting for encrypted mount..."
      for i in {1..20}; do
        if mountpoint -q /mnt/secure && [ -d /mnt/secure/freqtrade-bot ]; then
          echo "Encrypted mount is ready."
          break
        fi
        echo "Mount not ready, retrying in 3s..."
        sleep 3
      done
      if ! mountpoint -q /mnt/secure; then
        echo "ERROR: Encrypted mount not available. Exiting."
        exit 1
      fi

    # Start docker-compose as freqtrade with docker group perms
    - runuser -l freqtrade -c "newgrp docker <<EOC
        cd /mnt/secure/freqtrade-bot
        docker-compose down || true
        docker-compose up -d --build
      EOC"

    # Clean up sensitive pass file
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
