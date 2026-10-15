# Compute Engine ops VM: the way into the private network.
#
# No public IP, no SSH keys: access is
#   gcloud compute ssh <name> --zone <zone> --tunnel-through-iap
# with OS Login, so who logged in is tied to a Google identity and in the
# audit log. Used for Kafka admin tools and kubectl against the private
# control plane.

resource "google_service_account" "this" {
  account_id   = "${var.name}-sa"
  display_name = "Ops VM ${var.name} (no project roles)"
}

resource "google_compute_instance" "this" {
  name         = var.name
  zone         = var.zone
  machine_type = var.machine_type
  tags         = ["iap-ssh"]
  labels       = var.labels

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 20
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = var.subnet_id
    # no access_config block: no public IP
  }

  service_account {
    email  = google_service_account.this.email
    scopes = ["cloud-platform"] # actual permissions come from IAM roles (none)
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin         = "TRUE"
    block-project-ssh-keys = "TRUE"
  }
}
