terraform {
  backend "gcs" {
    # Output "state_bucket" of infra/gcp/bootstrap. GCS locks the state
    # natively: two applies can never run at the same time.
    bucket = "REPLACE-ME-project-id-tfstate"
    prefix = "kafka-sre-platform/dev"
  }
}
