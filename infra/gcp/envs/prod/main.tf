# Prod environment: same building blocks as dev, sized and protected for
# production: regional cluster (3 zones), HA Redis, deletion protection.
#
#   terraform -chdir=infra/gcp/envs/prod init
#   terraform -chdir=infra/gcp/envs/prod plan
#

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  default_labels = local.labels
}

locals {
  name = "kafka-sre-${var.environment}"
  labels = {
    project     = "kafka-sre-platform"
    environment = var.environment
    managed-by  = "terraform"
  }
}

module "network" {
  source = "../../modules/network"
  name   = local.name
  region = var.region
}

module "gke" {
  source              = "../../modules/gke"
  project_id          = var.project_id
  name                = local.name
  location            = var.region # regional: control plane and nodes in 3 zones
  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  machine_type        = "n2-standard-8"
  min_nodes           = 1 # per zone: 3 nodes, one per zone
  max_nodes           = 2
  deletion_protection = true
  labels              = local.labels
  authorized_networks = concat(
    [{ name = "vpc-subnet", cidr = module.network.subnet_cidr }],
    var.admin_cidrs,
  )
}

module "bastion" {
  source    = "../../modules/bastion"
  name      = "${local.name}-ops"
  zone      = var.zone
  subnet_id = module.network.subnet_id
  labels    = local.labels
}

module "redis" {
  source         = "../../modules/redis"
  name           = "${local.name}-prices"
  region         = var.region
  network_id     = module.network.network_id
  tier           = "STANDARD_HA"
  memory_size_gb = 5
  labels         = local.labels
}

module "registry" {
  source = "../../modules/registry"
  name   = "kafka-sre-platform"
  region = var.region
  labels = local.labels
}

module "monitoring" {
  source      = "../../modules/monitoring"
  name        = local.name
  alert_email = var.alert_email
  labels      = local.labels
}
