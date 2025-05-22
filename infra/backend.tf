terraform {
  backend "remote" {
    organization = "freqcap"
    workspaces {
      name = "freqtrade-infra"
    }
  }
}
