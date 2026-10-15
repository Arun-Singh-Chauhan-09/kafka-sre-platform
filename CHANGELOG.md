# Changelog

All notable changes follow [Keep a Changelog](https://keepachangelog.com/)
and [Semantic Versioning](https://semver.org/). Releases are cut by pushing a
`vX.Y.Z` tag (`make release VERSION=X.Y.Z`); the release workflow builds the
image and moves the GitOps pointer.

## [Unreleased]

## [0.1.0] - 2026-10-13
### Added
- Kafka on Kubernetes with Strimzi 0.51: 3 KRaft nodes (controller + broker),
  replication 3, `min.insync.replicas` 2, topics as `KafkaTopic` resources,
  JMX metrics and Kafka Exporter (consumer lag).
- Price pipeline: idempotent `acks=all` producer; consumer group with
  at-least-once processing, dead-letter topic for bad events, retry with
  backoff (no data loss) when Redis is down; Redis sink.
- SLOs and alerting: freshness SLO (99% of events in Redis within 5 s),
  15 alerts with multi-window burn rate, Alertmanager routing and inhibition,
  promtool unit tests, amtool routing tests.
- A runbook per alert, linked from the alert; CI fails if one is missing.
- Chaos drills: broker kill, consumers down, slow consumers, processing
  errors, Redis outage.
- Grafana dashboard as code (pipeline, Kafka health, logs from Loki).
- GitOps with ArgoCD; stateful Kafka resources protected from pruning.
- Policy as code: Kafka durability rules, workload security rules, GCP
  Terraform rules, all with unit tests.
- GCP track in Terraform: bootstrap with Workload Identity Federation,
  private GKE, Compute Engine ops VM (IAP only), Memorystore (AUTH + TLS),
  Artifact Registry, Cloud Monitoring alerts; dev and prod environments.
- CI: tests, Trivy (checksum-pinned), gitleaks, Terraform validate and an
  offline plan + policy gate that needs no cloud account, strict schema
  validation against the exact CRD versions, shellcheck. Tag-driven release
  to GHCR with SBOM and provenance.
