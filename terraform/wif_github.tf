# GitHub Actions to GCP.
#
# Two paths are built side by side against one pool, because the interesting
# question is not "how do I authenticate GitHub to GCP" but "which of the two
# ways should I use". See README for when each is correct.
#
#   Path 1: direct resource access. The federated principal is granted a role
#           on a resource. No service account exists.
#   Path 2: service account impersonation. The federated principal is granted
#           permission to impersonate a service account, and acts as it.

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-${var.pool_suffix}"
  display_name              = "GitHub Actions"
  description               = "Federates GitHub Actions OIDC tokens from a single repository."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  # checkov:skip=CKV_GCP_125: the check requires an equality test on
  # assertion.sub in claim:value form. This provider pins the repository and its
  # owner instead, which is Google's documented pattern and admits every ref of
  # one repository so authority can be split by ref in the IAM bindings below.
  # Pinning sub to a single value would collapse read and write into one
  # identity and deny pull request runs at the pool rather than scoping them.
  # The condition is not weaker than the check wants, it enforces another axis.
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC"

  # The mapping decides what the token's claims are called on the GCP side.
  # It does NOT decide who is allowed in. That is attribute_condition below.
  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
    "attribute.workflow"         = "assertion.workflow"
  }

  # This is the security control of the entire build.
  #
  # Without it, the provider trusts every token GitHub's issuer signs, which is
  # every workflow run in every repository on GitHub. An attacker creates a
  # public repo, runs a workflow, and receives a valid token for this pool. The
  # bindings below are scoped by attribute.repository, which limits the damage,
  # but the pool itself should refuse the token before binding evaluation ever
  # happens. Deny at the door, then scope inside it.
  attribute_condition = <<-EOT
    assertion.repository_owner == "${var.github_owner}" &&
    assertion.repository == "${var.github_repo}"
  EOT

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

locals {
  # Every principal from the allowed repository, regardless of branch.
  # Read access only.
  gh_repo_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"

  # Only runs on the deploy ref. Write access is scoped to this, so a pull
  # request from a fork cannot reach it.
  gh_deploy_principal = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.ref/${var.github_deploy_ref}"
}

# ---------------------------------------------------------------------------
# Path 1: direct resource access. No service account in this section at all.
# ---------------------------------------------------------------------------

# Access logs for the artifacts bucket. Federated access is the thing being
# demonstrated, so there should be a record of it that does not depend on the
# demo narrating its own success.
resource "google_storage_bucket" "logs" {
  name     = "${var.project_id}-logs"
  project  = var.project_id
  location = var.region
  labels   = var.labels

  # checkov:skip=CKV_GCP_62: this is the log bucket. Access logging has to
  # terminate somewhere, and pointing it at itself trips CKV_GCP_63 while
  # pointing it at a further bucket only moves the same question one hop.
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "artifacts" {
  name     = "${var.project_id}-artifacts"
  project  = var.project_id
  location = var.region
  labels   = var.labels

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Demo bucket holding nothing of value. Destroy should not need a manual
  # emptying pass.
  force_destroy = true

  versioning {
    enabled = true
  }

  logging {
    log_bucket        = google_storage_bucket.logs.name
    log_object_prefix = "artifacts/"
  }
}

# Any run from the repository can read.
resource "google_storage_bucket_iam_member" "gh_read" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectViewer"
  member = local.gh_repo_principal
}

# Only runs on the deploy ref can write.
resource "google_storage_bucket_iam_member" "gh_write" {
  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectCreator"
  member = local.gh_deploy_principal
}

resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "images"
  description   = "Container images. Federated CI pushes here without a key."
  format        = "DOCKER"
  labels        = var.labels

  # Same key as Secret Manager. One key to disable if the project has to be cut
  # off in a hurry, and the registry location has to match the key location.
  kms_key_name = google_kms_crypto_key.secrets.id

  depends_on = [google_kms_crypto_key_iam_member.artifactregistry_agent]
}

resource "google_artifact_registry_repository_iam_member" "gh_push" {
  project    = google_artifact_registry_repository.images.project
  location   = google_artifact_registry_repository.images.location
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = local.gh_deploy_principal
}

# ---------------------------------------------------------------------------
# Path 2: service account impersonation, for comparison.
# ---------------------------------------------------------------------------

resource "google_service_account" "deployer" {
  project      = var.project_id
  account_id   = "gh-deployer"
  display_name = "GitHub Actions deployer"
  description  = "Impersonated by federated GitHub runs on the deploy ref. Holds no keys, and org policy forbids creating any."
}

# The binding that makes impersonation possible. Scoped to the deploy ref, not
# the whole repository.
resource "google_service_account_iam_member" "deployer_impersonation" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.gh_deploy_principal
}

# What the impersonated identity can actually do. Kept deliberately small so
# the blast radius of the impersonation path is visible next to path 1.
resource "google_project_iam_member" "deployer_viewer" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}
