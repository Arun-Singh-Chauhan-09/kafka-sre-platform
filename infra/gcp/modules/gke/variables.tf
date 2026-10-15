variable "project_id" {
  type = string
}

variable "name" {
  type        = string
  description = "Cluster name, e.g. kafka-sre-dev."
}

variable "location" {
  type        = string
  description = "Zone (zonal cluster) or region (regional cluster)."
}

variable "network_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "pods_range_name" {
  type = string
}

variable "services_range_name" {
  type = string
}

variable "master_cidr" {
  type        = string
  description = "/28 for the control plane's private endpoint."
  default     = "172.16.0.32/28"
}

variable "authorized_networks" {
  type = list(object({
    name = string
    cidr = string
  }))
  description = "Networks allowed to reach the Kubernetes API."
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "min_nodes" {
  type    = number
  default = 3
}

variable "max_nodes" {
  type    = number
  default = 4
}

variable "deletion_protection" {
  type    = bool
  default = true
}

variable "labels" {
  type    = map(string)
  default = {}
}
