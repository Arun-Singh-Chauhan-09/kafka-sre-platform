# Unit tests for the GCP guardrails:  conftest verify --policy policy

package main

import rego.v1

plan_with(type, after) := {"resource_changes": [{
	"address": sprintf("%s.test", [type]),
	"type": type,
	"change": {"actions": ["create"], "after": after},
}]}

test_public_bucket_denied if {
	count(deny) > 0 with input as plan_with("google_storage_bucket", {"uniform_bucket_level_access": true, "public_access_prevention": "inherited"})
}

test_private_bucket_allowed if {
	count(deny) == 0 with input as plan_with("google_storage_bucket", {
		"uniform_bucket_level_access": true,
		"public_access_prevention": "enforced",
		"effective_labels": {"environment": "dev"},
	})
}

test_all_users_iam_denied if {
	count(deny) > 0 with input as plan_with("google_storage_bucket_iam_member", {"role": "roles/storage.objectViewer", "member": "allUsers"})
}

test_all_users_in_binding_denied if {
	count(deny) > 0 with input as plan_with("google_project_iam_binding", {"role": "roles/viewer", "members": ["user:a@example.com", "allAuthenticatedUsers"]})
}

test_primitive_role_denied if {
	count(deny) > 0 with input as plan_with("google_project_iam_member", {"role": "roles/editor", "member": "serviceAccount:ci@p.iam.gserviceaccount.com"})
}

test_predefined_role_allowed if {
	count(deny) == 0 with input as plan_with("google_project_iam_member", {"role": "roles/container.admin", "member": "serviceAccount:ci@p.iam.gserviceaccount.com"})
}

test_public_vm_denied if {
	count(deny) > 0 with input as plan_with("google_compute_instance", {
		"network_interface": [{"access_config": [{"nat_ip": null}]}],
		"shielded_instance_config": [{"enable_secure_boot": true}],
	})
}

test_private_shielded_vm_allowed if {
	count(deny) == 0 with input as plan_with("google_compute_instance", {
		"network_interface": [{"access_config": []}],
		"shielded_instance_config": [{"enable_secure_boot": true}],
	})
}

test_ssh_from_internet_denied if {
	count(deny) > 0 with input as plan_with("google_compute_firewall", {
		"direction": "INGRESS",
		"source_ranges": ["0.0.0.0/0"],
		"allow": [{"protocol": "tcp", "ports": ["22"]}],
	})
}

test_ssh_from_iap_allowed if {
	count(deny) == 0 with input as plan_with("google_compute_firewall", {
		"direction": "INGRESS",
		"source_ranges": ["35.235.240.0/20"],
		"allow": [{"protocol": "tcp", "ports": ["22"]}],
	})
}

good_cluster := {
	"private_cluster_config": [{"enable_private_nodes": true}],
	"workload_identity_config": [{"workload_pool": "p.svc.id.goog"}],
	"enable_legacy_abac": false,
	"effective_labels": {"environment": "dev"},
}

test_hardened_cluster_allowed if {
	count(deny) == 0 with input as plan_with("google_container_cluster", good_cluster)
	count(warn) == 0 with input as plan_with("google_container_cluster", good_cluster)
}

test_public_nodes_denied if {
	bad := json.patch(good_cluster, [{"op": "replace", "path": "/private_cluster_config/0/enable_private_nodes", "value": false}])
	count(deny) > 0 with input as plan_with("google_container_cluster", bad)
}

test_cluster_without_workload_identity_denied if {
	bad := json.patch(good_cluster, [{"op": "replace", "path": "/workload_identity_config", "value": []}])
	count(deny) > 0 with input as plan_with("google_container_cluster", bad)
}

test_node_pool_exposing_metadata_denied if {
	count(deny) > 0 with input as plan_with("google_container_node_pool", {"node_config": [{
		"workload_metadata_config": [{"mode": "GCE_METADATA"}],
		"shielded_instance_config": [{"enable_secure_boot": true}],
	}]})
}

test_redis_without_tls_denied if {
	count(deny) > 0 with input as plan_with("google_redis_instance", {"auth_enabled": true, "transit_encryption_mode": "DISABLED"})
}

test_missing_environment_label_warns if {
	count(warn) > 0 with input as plan_with("google_compute_instance", {
		"network_interface": [{"access_config": []}],
		"shielded_instance_config": [{"enable_secure_boot": true}],
		"effective_labels": {"project": "x"},
	})
}

test_deleted_resources_ignored if {
	count(deny) == 0 with input as {"resource_changes": [{
		"address": "google_storage_bucket.old",
		"type": "google_storage_bucket",
		"change": {"actions": ["delete"], "after": null},
	}]}
}
