# Memorystore for Redis: the managed replacement for the in-cluster Redis
# used locally. Reachable only from the VPC, AUTH required, TLS in transit.

resource "google_redis_instance" "this" {
  name           = var.name
  region         = var.region
  tier           = var.tier # BASIC (dev) or STANDARD_HA (prod: replica + failover)
  memory_size_gb = var.memory_size_gb
  redis_version  = "REDIS_7_2"

  authorized_network      = var.network_id
  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  redis_configs = {
    maxmemory-policy = "allkeys-lru" # it's a cache of the latest prices
  }

  maintenance_policy {
    weekly_maintenance_window {
      day = "TUESDAY"
      start_time {
        hours   = 7
        minutes = 0
      }
    }
  }

  labels = var.labels
}
