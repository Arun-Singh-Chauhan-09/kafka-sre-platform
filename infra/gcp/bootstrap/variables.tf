variable "project_id" {
  type        = string
  description = "GCP project to bootstrap."
}

variable "region" {
  type        = string
  description = "Region for the state bucket (europe-west3 = Frankfurt)."
  default     = "europe-west3"
}

variable "github_repository" {
  type        = string
  description = "owner/repo allowed to authenticate from GitHub Actions."
  default     = "Arun-Singh-Chauhan-09/kafka-sre-platform"
}
