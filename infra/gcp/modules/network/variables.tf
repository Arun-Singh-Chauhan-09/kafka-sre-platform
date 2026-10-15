variable "name" {
  type        = string
  description = "Name prefix, e.g. kafka-sre-dev."
}

variable "region" {
  type = string
}

variable "nodes_cidr" {
  type        = string
  description = "Primary range: GKE nodes and VMs."
  default     = "10.10.0.0/20"
}

variable "pods_cidr" {
  type        = string
  description = "Secondary range for pod IPs."
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  type        = string
  description = "Secondary range for Service ClusterIPs."
  default     = "10.30.0.0/20"
}
