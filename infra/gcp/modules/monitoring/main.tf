# Cloud Monitoring alert policies for what the in-cluster Prometheus cannot
# see well: the disks under Kafka, the managed Redis, and pods restarting.
# Kafka and pipeline alerts (lag, ISR, SLO) stay in Prometheus, defined
# once in git and identical on kind and on GKE.

locals {
  channels = var.alert_email == "" ? [] : [google_monitoring_notification_channel.email[0].id]
  runbooks = "https://github.com/Arun-Singh-Chauhan-09/kafka-sre-platform/blob/main/runbooks"
}

resource "google_monitoring_notification_channel" "email" {
  count        = var.alert_email == "" ? 0 : 1
  display_name = "${var.name} on-call email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

resource "google_monitoring_alert_policy" "kafka_disk" {
  display_name          = "${var.name}: Kafka broker disk above 80%"
  combiner              = "OR"
  severity              = "WARNING"
  notification_channels = local.channels

  conditions {
    display_name = "Kafka PVC utilization > 80% for 10 min"
    condition_threshold {
      filter          = "resource.type = \"k8s_pod\" AND resource.labels.namespace_name = \"kafka\" AND metric.type = \"kubernetes.io/pod/volume/utilization\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "600s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "A full disk stops the broker. Lower retention on the biggest topic (KafkaTopic in git) or grow the PVC (KafkaNodePool storage size). Runbook index: ${local.runbooks}/README.md"
  }

  user_labels = var.labels
}

resource "google_monitoring_alert_policy" "redis_memory" {
  display_name          = "${var.name}: Memorystore memory above 80%"
  combiner              = "OR"
  severity              = "WARNING"
  notification_channels = local.channels

  conditions {
    display_name = "Redis memory usage ratio > 0.8 for 10 min"
    condition_threshold {
      filter          = "resource.type = \"redis_instance\" AND metric.type = \"redis.googleapis.com/stats/memory/usage_ratio\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0.8
      duration        = "600s"
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_MAX"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "allkeys-lru evicts old prices first, so this is a capacity warning, not an outage. Raise memory_size_gb in infra/gcp/envs/<env>. Related: ${local.runbooks}/StreamSinkUnavailable.md"
  }

  user_labels = var.labels
}

resource "google_monitoring_alert_policy" "restarts" {
  display_name          = "${var.name}: containers restarting in kafka/streaming"
  combiner              = "OR"
  severity              = "WARNING"
  notification_channels = local.channels

  conditions {
    display_name = "More than 3 restarts in 15 min"
    condition_threshold {
      filter          = "resource.type = \"k8s_container\" AND (resource.labels.namespace_name = \"kafka\" OR resource.labels.namespace_name = \"streaming\") AND metric.type = \"kubernetes.io/container/restart_count\""
      comparison      = "COMPARISON_GT"
      threshold_value = 3
      duration        = "0s"
      aggregations {
        alignment_period   = "900s"
        per_series_aligner = "ALIGN_DELTA"
      }
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "Crash loops: check kubectl describe pod (OOMKilled?) and the previous logs. Runbooks: ${local.runbooks}/KafkaBrokerDown.md, ${local.runbooks}/StreamConsumerDown.md"
  }

  user_labels = var.labels
}
