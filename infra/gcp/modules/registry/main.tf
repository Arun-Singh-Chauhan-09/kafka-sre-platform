# Artifact Registry for the app image. Tags are immutable: a version
# number always means the same image, which is what GitOps relies on.

resource "google_artifact_registry_repository" "this" {
  repository_id = var.name
  location      = var.region
  format        = "DOCKER"
  description   = "Images for kafka-sre-platform"
  labels        = var.labels

  docker_config {
    immutable_tags = true
  }

  # Keep the 20 most recent versions; delete untagged images after a week.
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }

  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }
}
