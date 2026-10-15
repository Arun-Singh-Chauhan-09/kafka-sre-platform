# Dev environment: everything the platform needs on GCP, at the lowest cost
# that still behaves like production (3 Kafka nodes, private cluster).
#
#   terraform -chdir=infra/gcp/envs/dev init
#   terraform -chdir=infra/gcp/envs/dev plan
#
# Rough cost while running: ~10-15 EUR/day (3 x e2-standard-4, NAT,
# Memorystore 1 GB). Destroy after a demo: terraform ... destroy.

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
  location            = var.zone # zonal: one control plane, cheaper
  network_id          = module.network.network_id
  subnet_id           = module.network.subnet_id
  pods_range_name     = module.network.pods_range_name
  services_range_name = module.network.services_range_name
  machine_type        = "e2-standard-4"
  min_nodes           = 3
  max_nodes           = 4
  deletion_protection = false # dev is meant to be destroyed after a demo
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
  tier           = "BASIC"
  memory_size_gb = 1
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
