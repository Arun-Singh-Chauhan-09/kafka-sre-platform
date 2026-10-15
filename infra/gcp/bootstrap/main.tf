# One-time bootstrap per GCP project, applied by a human with local state:
#
#   terraform -chdir=infra/gcp/bootstrap init
#   terraform -chdir=infra/gcp/bootstrap apply -var project_id=<your-project>
#
# Creates what every other Terraform run needs and cannot create for itself:
#   - the APIs the platform uses
#   - a GCS bucket for remote state (versioned, private)
#   - Workload Identity Federation: GitHub Actions authenticates to GCP with
#     a short-lived OIDC token. No service account keys exist anywhere.
#   - two CI service accounts: "plan" (read-only, any branch / PR) and
#     "deploy" (can change infrastructure, main branch only)

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
}

locals {
  apis = [
    "artifactregistry.googleapis.com",
    "compute.googleapis.com",
    "container.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "iap.googleapis.com",
    "monitoring.googleapis.com",
    "redis.googleapis.com",
    "sts.googleapis.com",
  ]
}

resource "google_project_service" "apis" {
  for_each           = toset(local.apis)
  service            = each.value
  disable_on_destroy = false
}

# --- Terraform state ----------------------------------------------------------
resource "google_storage_bucket" "tfstate" {
  name                        = "${var.project_id}-tfstate"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true # every state version can be restored
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  labels = {
    project     = "kafka-sre-platform"
    environment = "shared"
    managed-by  = "terraform"
  }
}

# --- GitHub Actions -> GCP without keys ---------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  # Only tokens issued for this one repository are accepted at all.
  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "plan" {
  account_id   = "gh-terraform-plan"
  display_name = "GitHub Actions: terraform plan (read-only)"
}

resource "google_service_account" "deploy" {
  account_id   = "gh-terraform-deploy"
  display_name = "GitHub Actions: terraform apply (main branch only)"
}

# Any workflow run of the repository (pull requests included) may plan.
resource "google_service_account_iam_member" "plan_wif" {
  service_account_id = google_service_account.plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# Only runs on refs/heads/main may deploy.
resource "google_service_account_iam_member" "deploy_wif" {
  service_account_id = google_service_account.deploy.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/refs/heads/main"
}

resource "google_project_iam_member" "plan" {
  for_each = toset(["roles/viewer", "roles/iam.securityReviewer"])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.plan.email}"
}

# Scoped roles instead of roles/editor or roles/owner (the policy gate
# blocks primitive roles).
resource "google_project_iam_member" "deploy" {
  for_each = toset([
    "roles/artifactregistry.admin",
    "roles/compute.instanceAdmin.v1",
    "roles/compute.networkAdmin",
    "roles/compute.securityAdmin",
    "roles/container.admin",
    "roles/iam.serviceAccountAdmin",
    "roles/iam.serviceAccountUser",
    "roles/monitoring.editor",
    "roles/redis.admin",
    "roles/resourcemanager.projectIamAdmin",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deploy.email}"
}

# Both need the state bucket: plan takes the state lock too.
resource "google_storage_bucket_iam_member" "state" {
  for_each = {
    plan   = google_service_account.plan.email
    deploy = google_service_account.deploy.email
  }
  bucket = google_storage_bucket.tfstate.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${each.value}"
}
