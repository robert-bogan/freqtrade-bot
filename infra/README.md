# Terraform: Hetzner Freqtrade Infra

## 🚀 Setup

1. Install Terraform
2. Export your Hetzner Cloud API token
3. Add your SSH key to Hetzner Cloud

## 🧩 Steps

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
# Edit with your API key + SSH key name

terraform init
terraform apply
```

Once deployed, output will include the IP address to use in GitHub secrets (`SERVER_IP`).
