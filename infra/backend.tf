terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "freqcap"

    workspaces {
      name = "freqtrade-infra"
    }
  }
}

