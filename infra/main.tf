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
    - curl

  write_files:
    - path: /root/gocryptfs_pass
      permissions: '0600'
      owner: root:root
      content: "${var.gocryptfs_pass}"

  runcmd:
    # Enable Docker
    - systemctl enable docker
    - systemctl start docker

    # Prepare and initialize gocryptfs (only if not already initialized)
    - mkdir -p /mnt/secure_raw /mnt/secure
    - if [ ! -f /mnt/secure_raw/gocryptfs.conf ]; then \
          echo -n "${var.gocryptfs_pass}" | gocryptfs -init /mnt/secure_raw; \
      fi

    # Mount encrypted volume
    - mkdir -p /mnt/secure_raw /mnt/secure
    - if [ ! -f /mnt/secure_raw/gocryptfs.conf ]; then
        printf "%s" "${var.gocryptfs_pass}" | gocryptfs -q -init /mnt/secure_raw;
      fi
    - if [ -f /mnt/secure_raw/gocryptfs.conf ]; then
        printf "%s" "${var.gocryptfs_pass}" | gocryptfs -allow_other /mnt/secure_raw /mnt/secure;
      else
        echo "ERROR: Missing gocryptfs.conf after init!" && exit 1;
      fi

    # Wait for mount to be ready
    - |
      for i in $(seq 1 10); do
        mountpoint -q /mnt/secure && break
        echo 'Waiting for encrypted mount...'
        sleep 3
      done
      mountpoint -q /mnt/secure || { echo 'ERROR: Encrypted mount not available. Exiting.'; exit 1; }

    # Clone the freqtrade repo
    - sudo -u freqtrade git clone https://github.com/robert-bogan/freqtrade-bot.git /mnt/secure/freqtrade-bot

    # Copy config and set permissions
    - sudo -u freqtrade mkdir -p /mnt/secure/freqtrade-bot/user_data
    - cp /mnt/secure/freqtrade-bot/config/config.json /mnt/secure/freqtrade-bot/user_data/config.json
    - chown -R freqtrade:freqtrade /mnt/secure/freqtrade-bot

    # Create .env file
    - echo "POSTGRES_PASSWORD=${var.postgres_password}" > /mnt/secure/freqtrade-bot/config/.env
    - chown freqtrade:freqtrade /mnt/secure/freqtrade-bot/config/.env

    # Build and start Docker containers
    - cd /mnt/secure/freqtrade-bot && sudo -u freqtrade docker-compose up -d --build

    # Clean up sensitive files
    # - rm -f /root/gocryptfs_pass
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
