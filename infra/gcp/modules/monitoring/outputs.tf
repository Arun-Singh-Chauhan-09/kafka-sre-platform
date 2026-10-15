output "alert_policy_ids" {
  value = [
    google_monitoring_alert_policy.kafka_disk.id,
    google_monitoring_alert_policy.redis_memory.id,
    google_monitoring_alert_policy.restarts.id,
  ]
}
