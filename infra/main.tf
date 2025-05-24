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
    - python3-pip
    - docker.io
    - docker-compose

  write_files:
    - path: /root/gocryptfs_pass
      permissions: '0600'
      owner: root:root
      content: "${var.gocryptfs_pass}"

  runcmd:
    # 1. Prepare disk
    - parted /dev/sdb mklabel gpt
    - parted -a opt /dev/sdb mkpart primary ext4 0% 100%
    - sleep 2

    # 2. Format and mount encrypted filesystem
    - mkdir -p /mnt/secure_raw
    - echo "${var.gocryptfs_pass}" > /root/gocryptfs_pass
    - echo "${var.gocryptfs_pass}" | gocryptfs -init /mnt/secure_raw
    - echo "${var.gocryptfs_pass}" | gocryptfs /mnt/secure_raw /mnt/secure
    - chmod 700 /mnt/secure
    - rm -f /root/gocryptfs_pass

    # 3. Now install and set up docker + app
    - systemctl enable docker
    - systemctl start docker
    - mkdir -p /mnt/secure/freqtrade-bot
    - git clone https://github.com/robert-bogan/freqtrade-bot /mnt/secure/freqtrade-bot
    - cd /mnt/secure/freqtrade-bot
    - pip3 install poetry
    - poetry install
    - usermod -aG docker root

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
