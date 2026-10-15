output "image_prefix" {
  description = "e.g. europe-west3-docker.pkg.dev/<project>/<repo>"
  value       = "${var.region}-docker.pkg.dev/${google_artifact_registry_repository.this.project}/${google_artifact_registry_repository.this.repository_id}"
}
