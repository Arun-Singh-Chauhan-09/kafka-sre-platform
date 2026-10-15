# Private GKE cluster for Kafka (Strimzi) and the streaming apps.
#
#  - private nodes: no public IPs; outbound through Cloud NAT
#  - control plane reachable only from the authorized networks
#  - Workload Identity: pods get Google credentials through their Kubernetes
#    service account, never through node credentials or keys
#  - Dataplane V2: Kubernetes NetworkPolicies are enforced
#  - node pool: surge upgrades one node at a time (Kafka keeps quorum)

resource "google_service_account" "nodes" {
  account_id   = "${var.name}-nodes"
  display_name = "GKE nodes for ${var.name}"
}

# Least privilege for the nodes themselves (instead of the default compute
# service account, which has roles/editor).
resource "google_project_iam_member" "nodes" {
  for_each = toset([
    "roles/artifactregistry.reader",
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/monitoring.viewer",
    "roles/stackdriver.resourceMetadata.writer",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.nodes.email}"
}

resource "google_container_cluster" "this" {
  name     = var.name
  location = var.location # a zone (dev, cheaper) or a region (prod, 3 zones)

  network         = var.network_id
  subnetwork      = var.subnet_id
  networking_mode = "VPC_NATIVE"

  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  # Node pools are managed separately below.
  remove_default_node_pool = true
  initial_node_count       = 1

  release_channel {
    channel = var.release_channel
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.authorized_networks
      content {
        cidr_block   = cidr_blocks.value.cidr
        display_name = cidr_blocks.value.name
      }
    }
  }

  datapath_provider = "ADVANCED_DATAPATH" # Dataplane V2: NetworkPolicy enforcement

  logging_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
  }

  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
  }

  maintenance_policy {
    recurring_window {
      # Weekday mornings (UTC): upgrades happen while people are at work.
      start_time = "2026-01-01T07:00:00Z"
      end_time   = "2026-01-01T11:00:00Z"
      recurrence = "FREQ=WEEKLY;BYDAY=TU,WE,TH"
    }
  }

  resource_labels = var.labels

  deletion_protection = var.deletion_protection
}

resource "google_container_node_pool" "kafka" {
  name     = "kafka"
  cluster  = google_container_cluster.this.id
  location = var.location

  # Per zone. A regional cluster (prod) multiplies this by 3.
  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  # One node at a time, a new one first: Kafka keeps 2 of 3 replicas in
  # sync during node upgrades, and the PodDisruptionBudget Strimzi creates
  # stops two brokers being drained at once.
  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
  }

  node_config {
    machine_type    = var.machine_type
    disk_type       = "pd-balanced"
    disk_size_gb    = 50
    service_account = google_service_account.nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]
    labels          = var.labels

    workload_metadata_config {
      mode = "GKE_METADATA" # pods cannot read the node's credentials
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }
}
