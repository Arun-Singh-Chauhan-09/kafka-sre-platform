output "kube_context" {
  description = "Context name to pass to kubectl --context."
  value       = "kind-${kind_cluster.this.name}"
}

output "endpoint" {
  value = kind_cluster.this.endpoint
}
