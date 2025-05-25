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

      - path: /mnt/secure/freqtrade-bot/config/.env
        permissions: '0600'
        owner: root:root
        content: |
          POSTGRES_PASSWORD=${var.postgres_password}

      - path: /mnt/secure/freqtrade-bot/config/config.json.template
        permissions: '0644'
        owner: root:root
        content: |
          {
            "dry_run": true,
            "strategy": "InitialStrategy",
            "exchange": {
              "name": "",
              "key": "",
              "secret": "",
              "password": "",
              "ccxt_config": {},
              "ccxt_async_config": {},
              "pair_whitelist": ["BTC/USDT"],
              "pair_blacklist": []
            },
            "telegram": {
              "enabled": true,
              "token": "",
              "chat_id": ""
            },
            "databases": {
              "driver": "postgresql",
              "host": "postgres",
              "port": 5432,
              "user": "freqtrade",
              "password": "${var.postgres_password}",
              "database": "freqtrade_db"
            }
          }

      - path: /mnt/secure/freqtrade-bot/docker-compose.yml
        permissions: '0644'
        owner: root:root
        content: |
          version: '3.8'
          services:
            freqtrade:
              image: freqtradeorg/freqtrade:stable
              container_name: freqtrade
              volumes:
                - ./user_data:/freqtrade/user_data
              env_file:
                - ./config/.env
              command: >
                trade
                --config /freqtrade/user_data/config.json
              restart: unless-stopped

            postgres:
              image: postgres:13
              container_name: freqtrade-db
              environment:
                POSTGRES_USER: freqtrade
                POSTGRES_PASSWORD: ${var.postgres_password}
                POSTGRES_DB: freqtrade_db
              volumes:
                - pgdata:/var/lib/postgresql/data
              restart: unless-stopped

          volumes:
            pgdata:

    runcmd:
      - systemctl enable docker
      - systemctl start docker

      # Setup gocryptfs
      - mkdir -p /mnt/secure_raw
      - mkdir -p /mnt/secure
      - echo "${var.gocryptfs_pass}" | gocryptfs -init /mnt/secure_raw
      - echo "${var.gocryptfs_pass}" | gocryptfs -allow_other -exec /mnt/secure_raw /mnt/secure

      # Create directories and render config
      - mkdir -p /mnt/secure/freqtrade-bot/user_data
      - chown -R root:root /mnt/secure/freqtrade-bot
      - export $(cat /mnt/secure/freqtrade-bot/config/.env | xargs)
      - envsubst < /mnt/secure/freqtrade-bot/config/config.json.template > /mnt/secure/freqtrade-bot/user_data/config.json

      # Start docker containers
      - docker compose -f /mnt/secure/freqtrade-bot/docker-compose.yml up -d --build

      # Clean up secrets
      - rm -f /root/gocryptfs_pass

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
