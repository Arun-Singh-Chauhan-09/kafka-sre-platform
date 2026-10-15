# Copy these into the GitHub repository settings
# (Settings -> Secrets and variables -> Actions).

output "state_bucket" {
  description = "Put this into infra/gcp/envs/*/backend.tf."
  value       = google_storage_bucket.tfstate.name
}

output "workload_identity_provider" {
  description = "Repository variable GCP_WORKLOAD_IDENTITY_PROVIDER."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "plan_service_account" {
  description = "Repository variable GCP_PLAN_SERVICE_ACCOUNT."
  value       = google_service_account.plan.email
}

output "deploy_service_account" {
  description = "Repository variable GCP_DEPLOY_SERVICE_ACCOUNT."
  value       = google_service_account.deploy.email
}
