# Kafka durability guardrails, run in CI against the rendered cluster:
#   kubectl kustomize kafka > rendered-kafka.yaml
#   conftest test --policy policy --namespace kafka rendered-kafka.yaml
#
# The settings that decide whether one broker failure loses data or stops
# writes are one-line YAML changes. These rules make that a failed pull
# request instead of an incident.

package kafka

import rego.v1

name := sprintf("%s/%s", [input.kind, input.metadata.name])

# --- topics -----------------------------------------------------------------
deny contains msg if {
	input.kind == "KafkaTopic"
	object.get(input, ["spec", "replicas"], 0) < 3
	msg := sprintf("%s: replicas must be at least 3 (one copy per node)", [name])
}

deny contains msg if {
	input.kind == "KafkaTopic"
	to_number(object.get(input, ["spec", "config", "min.insync.replicas"], 1)) < 2
	msg := sprintf("%s: min.insync.replicas must be at least 2, or acks=all only waits for one copy", [name])
}

deny contains msg if {
	input.kind == "KafkaTopic"
	isr := to_number(object.get(input, ["spec", "config", "min.insync.replicas"], 1))
	isr >= object.get(input, ["spec", "replicas"], 0)
	msg := sprintf("%s: min.insync.replicas must be lower than replicas, or any single node restart stops writes", [name])
}

warn contains msg if {
	input.kind == "KafkaTopic"
	not input.spec.config["retention.ms"]
	not input.spec.config["retention.bytes"]
	msg := sprintf("%s: no explicit retention; the broker default (7 days) applies", [name])
}

# --- cluster ----------------------------------------------------------------
deny contains msg if {
	input.kind == "Kafka"
	some key, minimum in {
		"default.replication.factor": 3,
		"min.insync.replicas": 2,
		"offsets.topic.replication.factor": 3,
	}
	to_number(object.get(input, ["spec", "kafka", "config", key], 1)) < minimum
	msg := sprintf("%s: %s must be at least %d", [name, key, minimum])
}

deny contains msg if {
	input.kind == "Kafka"
	not input.spec.kafka.metricsConfig
	msg := sprintf("%s: broker metrics (metricsConfig) must be enabled; the alerts depend on them", [name])
}

deny contains msg if {
	input.kind == "Kafka"
	not input.spec.kafkaExporter
	msg := sprintf("%s: kafkaExporter must be enabled; consumer lag alerts depend on it", [name])
}

warn contains msg if {
	input.kind == "Kafka"
	object.get(input, ["spec", "kafka", "config", "auto.create.topics.enable"], true) != false
	msg := sprintf("%s: auto.create.topics.enable should be false (topics only via KafkaTopic in git)", [name])
}

deny contains msg if {
	input.kind == "KafkaNodePool"
	"controller" in input.spec.roles
	input.spec.replicas < 3
	msg := sprintf("%s: a KRaft controller quorum needs at least 3 nodes to survive one failure", [name])
}
