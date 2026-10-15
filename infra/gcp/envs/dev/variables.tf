variable "project_id" {
  type        = string
  description = "GCP project ID."
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "region" {
  type    = string
  default = "europe-west3" # Frankfurt
}

variable "zone" {
  type    = string
  default = "europe-west3-a"
}

variable "admin_cidrs" {
  type = list(object({
    name = string
    cidr = string
  }))
  description = "Extra networks allowed to reach the Kubernetes API (e.g. your office IP /32)."
  default     = []
}

variable "alert_email" {
  type    = string
  default = ""
}
