# Local Kubernetes cluster for the free, laptop-only track.
#
# Terraform owns the cluster; ArgoCD owns what runs inside it. Same split as
# the GCP track (Terraform owns GKE, ArgoCD owns the workloads), so the
# mental model carries over.
#
#   terraform -chdir=infra/local-kind init
#   terraform -chdir=infra/local-kind apply

terraform {
  required_version = ">= 1.6"
  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.9"
    }
  }
}

provider "kind" {}

resource "kind_cluster" "this" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    # Everything is reached through kubectl port-forward (scripts/setup.sh),
    # so no host ports are bound when the cluster is created.
    node {
      role = "control-plane"
    }

    node {
      role = "worker"
    }
  }
}
