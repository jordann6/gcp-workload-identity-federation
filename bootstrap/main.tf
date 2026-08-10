# Bootstrap layer.
#
# Creates the smallest org scaffold the rest of the build needs: one folder, two
# projects, and the state bucket. Deliberately thin. The landing zone project
# later adopts this folder and these projects rather than standing up a parallel
# hierarchy, which is what adopting existing infrastructure actually looks like.
#
# The two-project split is the point of the whole build. Federated CI gets
# access to resources in the workload project only. State, which can contain
# the shape of everything, lives somewhere CI cannot reach.

resource "random_id" "suffix" {
  byte_length = 3
}

locals {
  bootstrap_project_id = "${var.name_prefix}-boot-${random_id.suffix.hex}"
  workload_project_id  = "${var.name_prefix}-work-${random_id.suffix.hex}"

  # Enabled on the bootstrap project: just enough to hold state.
  bootstrap_apis = [
    "storage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ]

  # Enabled on the workload project. sts and iamcredentials are the two that
  # matter for federation: sts exchanges the external token, iamcredentials
  # mints the access token when impersonation is used.
  workload_apis = [
    "artifactregistry.googleapis.com",
    "cloudkms.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "orgpolicy.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]
}

resource "google_folder" "platform" {
  display_name        = var.folder_name
  parent              = "organizations/${var.org_id}"
  deletion_protection = false
}

resource "google_project" "bootstrap" {
  name            = local.bootstrap_project_id
  project_id      = local.bootstrap_project_id
  folder_id       = google_folder.platform.folder_id
  billing_account = var.billing_account
  labels          = merge(var.labels, { layer = "bootstrap" })

  # Projects normally resist deletion. These are demo projects with a documented
  # teardown, so allow destroy to actually destroy. A deleted project is
  # recoverable for 30 days and its ID is never reusable.
  deletion_policy = "DELETE"

  # No default VPC. The default network ships with permissive firewall rules
  # (including SSH and RDP from anywhere) that nobody chose and few audit.
  auto_create_network = false
}

resource "google_project" "workload" {
  name            = local.workload_project_id
  project_id      = local.workload_project_id
  folder_id       = google_folder.platform.folder_id
  billing_account = var.billing_account
  labels          = merge(var.labels, { layer = "workload" })

  deletion_policy = "DELETE"

  # Same reasoning as the bootstrap project: no default VPC and no firewall
  # rules nobody chose.
  auto_create_network = false
}

resource "google_project_service" "bootstrap" {
  for_each = toset(local.bootstrap_apis)

  project = google_project.bootstrap.project_id
  service = each.value

  # Leave the APIs on when the project is torn down. Disabling a service on the
  # way out can fail on dependency ordering and strand a destroy halfway.
  disable_on_destroy = false
}

resource "google_project_service" "workload" {
  for_each = toset(local.workload_apis)

  project = google_project.workload.project_id
  service = each.value

  disable_on_destroy = false
}

# Audit logging. Admin activity logs are always on and free; these add the data
# access logs, which are what tell you who read state or read a secret. Volume
# here is tiny, so the cost is negligible, and a project about proving who
# accessed what should be able to answer that question.
resource "google_project_iam_audit_config" "bootstrap" {
  project = google_project.bootstrap.project_id
  service = "allServices"

  dynamic "audit_log_config" {
    for_each = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
    content {
      log_type = audit_log_config.value
    }
  }
}

resource "google_project_iam_audit_config" "workload" {
  project = google_project.workload.project_id
  service = "allServices"

  dynamic "audit_log_config" {
    for_each = ["ADMIN_READ", "DATA_READ", "DATA_WRITE"]
    content {
      log_type = audit_log_config.value
    }
  }
}

# Access logs for the state bucket: a record of who read state, kept separately
# from state itself.
resource "google_storage_bucket" "state_logs" {
  # checkov:skip=CKV_GCP_62: this is the log bucket, so access logging
  # terminates here rather than recursing.
  name     = "${local.bootstrap_project_id}-tfstate-logs"
  project  = google_project.bootstrap.project_id
  location = var.state_bucket_location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.bootstrap]
}

# Terraform state. Versioning is on so a corrupted or truncated state can be
# rolled back to the prior generation, which is the one recovery path that
# matters when a plan dies mid-apply.
resource "google_storage_bucket" "state" {
  name     = "${local.bootstrap_project_id}-tfstate"
  project  = google_project.bootstrap.project_id
  location = var.state_bucket_location

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = var.force_destroy_state

  versioning {
    enabled = true
  }

  logging {
    log_bucket        = google_storage_bucket.state_logs.name
    log_object_prefix = "tfstate/"
  }

  lifecycle_rule {
    condition {
      num_newer_versions = 20
    }
    action {
      type = "Delete"
    }
  }

  depends_on = [google_project_service.bootstrap]
}
