variable "cluster_name" {
  type        = string
  description = "kind cluster name. kubectl context becomes kind-<name>."
  default     = "kafka-sre"
}

variable "node_image" {
  type        = string
  description = "kindest/node image; pin it so every rebuild gets the same Kubernetes version."
  default     = "kindest/node:v1.31.0"
}
