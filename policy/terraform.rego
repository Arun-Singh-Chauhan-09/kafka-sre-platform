# Paved-road guardrails for the GCP infrastructure, enforced in CI against a
# Terraform plan:
#
#   terraform -chdir=infra/gcp/envs/dev plan -out tf.plan
#   terraform -chdir=infra/gcp/envs/dev show -json tf.plan > plan.json
#   conftest test --policy policy --namespace main plan.json
#
# Checkov knows generic best practice; these are the rules this platform
# chooses to block on.

package main

import rego.v1

# Resources being created or updated in this plan.
changed contains res if {
	some res in input.resource_changes
	some action in res.change.actions
	action in {"create", "update"}
}

after(res) := res.change.after

# --- 1. Nothing public ------------------------------------------------------
deny contains msg if {
	some res in changed
	res.type == "google_storage_bucket"
	after(res).public_access_prevention != "enforced"
	msg := sprintf("%s: public_access_prevention must be \"enforced\"", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "google_storage_bucket"
	not after(res).uniform_bucket_level_access
	msg := sprintf("%s: uniform_bucket_level_access must be true (no per-object ACLs)", [res.address])
}

deny contains msg if {
	some res in changed
	is_iam(res.type)
	some member in members(after(res))
	member in {"allUsers", "allAuthenticatedUsers"}
	msg := sprintf("%s: grants access to %s", [res.address, member])
}

deny contains msg if {
	some res in changed
	res.type == "google_compute_instance"
	some nic in after(res).network_interface
	count(object.get(nic, "access_config", [])) > 0
	msg := sprintf("%s: VMs get no public IP; reach them through IAP", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "google_compute_firewall"
	object.get(after(res), "direction", "INGRESS") == "INGRESS"
	"0.0.0.0/0" in object.get(after(res), "source_ranges", [])
	some rule in after(res).allow
	some port in object.get(rule, "ports", [])
	port in {"22", "3389"}
	msg := sprintf("%s: SSH/RDP open to the internet; use the IAP range 35.235.240.0/20", [res.address])
}

# --- 2. Least privilege -----------------------------------------------------
deny contains msg if {
	some res in changed
	is_iam(res.type)
	after(res).role in {"roles/owner", "roles/editor"}
	msg := sprintf("%s: primitive role %s; grant a predefined role instead", [res.address, after(res).role])
}

# --- 3. GKE hardening ---------------------------------------------------------
deny contains msg if {
	some res in changed
	res.type == "google_container_cluster"
	not private_nodes(after(res))
	msg := sprintf("%s: nodes must be private (private_cluster_config.enable_private_nodes)", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "google_container_cluster"
	count(object.get(after(res), "workload_identity_config", [])) == 0
	msg := sprintf("%s: Workload Identity must be enabled (no node credentials in pods)", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "google_container_cluster"
	after(res).enable_legacy_abac == true
	msg := sprintf("%s: legacy ABAC must be disabled (RBAC only)", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "google_container_node_pool"
	some nc in after(res).node_config
	not gke_metadata(nc)
	msg := sprintf("%s: workload_metadata_config.mode must be GKE_METADATA", [res.address])
}

deny contains msg if {
	some res in changed
	res.type in {"google_container_node_pool", "google_compute_instance"}
	not secure_boot(res)
	msg := sprintf("%s: Shielded VM secure boot must be enabled", [res.address])
}

# --- 4. Data in transit -------------------------------------------------------
deny contains msg if {
	some res in changed
	res.type == "google_redis_instance"
	not after(res).auth_enabled
	msg := sprintf("%s: Redis AUTH must be enabled", [res.address])
}

deny contains msg if {
	some res in changed
	res.type == "google_redis_instance"
	object.get(after(res), "transit_encryption_mode", "DISABLED") == "DISABLED"
	msg := sprintf("%s: Redis must use TLS (transit_encryption_mode)", [res.address])
}

# --- 5. Ownership: who pays for this? -----------------------------------------
warn contains msg if {
	some res in changed
	res.type in labelled
	labels := object.get(after(res), "effective_labels", object.get(after(res), "labels", {}))
	not labels.environment
	msg := sprintf("%s: missing an environment label", [res.address])
}

# --- helpers --------------------------------------------------------------------
labelled := {
	"google_container_cluster",
	"google_compute_instance",
	"google_redis_instance",
	"google_artifact_registry_repository",
	"google_storage_bucket",
}

is_iam(type) if endswith(type, "_iam_member")

is_iam(type) if endswith(type, "_iam_binding")

members(a) := {a.member} if a.member

members(a) := {m | some m in a.members} if a.members

private_nodes(a) if {
	some cfg in a.private_cluster_config
	cfg.enable_private_nodes == true
}

gke_metadata(nc) if {
	some wm in nc.workload_metadata_config
	wm.mode == "GKE_METADATA"
}

secure_boot(res) if {
	res.type == "google_compute_instance"
	some sic in after(res).shielded_instance_config
	sic.enable_secure_boot == true
}

secure_boot(res) if {
	res.type == "google_container_node_pool"
	some nc in after(res).node_config
	some sic in nc.shielded_instance_config
	sic.enable_secure_boot == true
}
