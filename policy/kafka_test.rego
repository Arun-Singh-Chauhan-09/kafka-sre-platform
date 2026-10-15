# Unit tests for the Kafka guardrails:  conftest verify --policy policy

package kafka

import rego.v1

topic(spec) := {"kind": "KafkaTopic", "metadata": {"name": "t"}, "spec": spec}

good_topic := topic({"partitions": 6, "replicas": 3, "config": {"min.insync.replicas": 2, "retention.ms": 86400000}})

good_cluster := {
	"kind": "Kafka",
	"metadata": {"name": "c"},
	"spec": {
		"kafka": {
			"config": {
				"default.replication.factor": 3,
				"min.insync.replicas": 2,
				"offsets.topic.replication.factor": 3,
				"auto.create.topics.enable": false,
			},
			"metricsConfig": {"type": "jmxPrometheusExporter"},
		},
		"kafkaExporter": {},
	},
}

test_good_topic_passes if {
	count(deny) == 0 with input as good_topic
	count(warn) == 0 with input as good_topic
}

test_single_replica_topic_denied if {
	count(deny) > 0 with input as topic({"replicas": 1, "config": {"min.insync.replicas": 2}})
}

test_min_isr_one_denied if {
	count(deny) > 0 with input as topic({"replicas": 3, "config": {"min.insync.replicas": 1}})
}

test_min_isr_equal_to_replicas_denied if {
	# 3 replicas, min ISR 3: restarting any node for an upgrade stops writes
	count(deny) > 0 with input as topic({"replicas": 3, "config": {"min.insync.replicas": 3}})
}

test_min_isr_as_string_is_understood if {
	count(deny) == 0 with input as topic({"replicas": 3, "config": {"min.insync.replicas": "2", "retention.ms": 1}})
}

test_missing_retention_warns if {
	count(warn) > 0 with input as topic({"replicas": 3, "config": {"min.insync.replicas": 2}})
}

test_good_cluster_passes if {
	count(deny) == 0 with input as good_cluster
	count(warn) == 0 with input as good_cluster
}

test_low_replication_factor_denied if {
	bad := json.patch(good_cluster, [{"op": "replace", "path": "/spec/kafka/config/default.replication.factor", "value": 1}])
	count(deny) > 0 with input as bad
}

test_missing_exporter_denied if {
	bad := json.patch(good_cluster, [{"op": "remove", "path": "/spec/kafkaExporter"}])
	count(deny) > 0 with input as bad
}

test_auto_create_topics_warns if {
	bad := json.patch(good_cluster, [{"op": "remove", "path": "/spec/kafka/config/auto.create.topics.enable"}])
	count(warn) > 0 with input as bad
}

test_two_node_controller_quorum_denied if {
	count(deny) > 0 with input as {
		"kind": "KafkaNodePool",
		"metadata": {"name": "p"},
		"spec": {"replicas": 2, "roles": ["controller", "broker"]},
	}
}
