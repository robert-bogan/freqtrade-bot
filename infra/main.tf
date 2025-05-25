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
    - parted
    - cryptsetup
    - gocryptfs
    - git
    - docker.io
    - docker-compose

  write_files:
    - path: /root/gocryptfs_pass
      permissions: '0600'
      owner: root:root
      content: "${var.gocryptfs_pass}"

  runcmd:
    # 1. Format & mount encrypted filesystem
    - mkdir -p /mnt/secure_raw
    - echo "${var.gocryptfs_pass}" > /root/gocryptfs_pass

    # Initialize gocryptfs only if not already set up
    - '[ ! -f /mnt/secure_raw/gocryptfs.conf ] && echo "${var.gocryptfs_pass}" | gocryptfs -init /mnt/secure_raw || true'

    # Mount encrypted FS
    - mkdir -p /mnt/secure
    - echo "${var.gocryptfs_pass}" | gocryptfs /mnt/secure_raw /mnt/secure
    - '[ -d /mnt/secure ] && chmod 700 /mnt/secure || (echo "Mount failed" && exit 1)'

    - rm -f /root/gocryptfs_pass

    # 2. Install & start Docker
    - systemctl enable docker
    - systemctl start docker
    - usermod -aG docker root

    # 3. Clone the repo only after /mnt/secure is available
    - git clone https://github.com/robert-bogan/freqtrade-bot /mnt/secure/freqtrade-bot

    # 4. Start Docker Compose stack (will be reconfigured later via GitHub Actions)
    - cd /mnt/secure/freqtrade-bot
    - docker-compose up -d --build || true

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
