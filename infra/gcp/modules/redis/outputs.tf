output "host" {
  value = google_redis_instance.this.host
}

output "port" {
  value = google_redis_instance.this.port
}

output "auth_string" {
  description = "Store in a Kubernetes Secret (REDIS_PASSWORD) for the consumer."
  value       = google_redis_instance.this.auth_string
  sensitive   = true
}

output "server_ca_cert" {
  description = "Mount as a file and point REDIS_CA_FILE at it (REDIS_TLS=true)."
  value       = google_redis_instance.this.server_ca_certs[0].cert
  sensitive   = true
}
