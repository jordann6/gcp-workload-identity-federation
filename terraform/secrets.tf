# Secret Manager with a customer-managed encryption key.
#
# The federated principal reads a secret with no credential of its own. That is
# the whole chain the build is meant to demonstrate: GitHub signs a token, GCP
# exchanges it for a short-lived access token, that token reads a secret
# encrypted with a key the caller never touches.
#
# CMEK here is not security theater against Google. It is the control that makes
# key revocation possible: disabling the key version makes every secret version
# under it unreadable immediately, without deleting anything or editing IAM.

resource "google_kms_key_ring" "secrets" {
  project = var.project_id
  name    = "secrets-${var.pool_suffix}"

  # A key ring is permanent. It cannot be deleted or moved, and its location is
  # fixed at creation. `terraform destroy` removes it from state and leaves the
  # ring in place. This is a GCP property, not an oversight, and it is called
  # out in the teardown section of the README.
  location = var.region
}

resource "google_kms_crypto_key" "secrets" {
  # checkov:skip=CKV_GCP_82: prevent_destroy is deliberately off. This is a
  # deploy-demo-destroy portfolio build with a documented teardown, and a key
  # guarded against destruction would strand every teardown after the first. In
  # a production project this check should hold and prevent_destroy stays on.
  name     = "secret-manager"
  key_ring = google_kms_key_ring.secrets.id
  purpose  = "ENCRYPT_DECRYPT"

  # 90 days. Rotation creates a new primary version; existing secret versions
  # stay readable under the version that encrypted them.
  rotation_period = "7776000s"

  version_template {
    algorithm        = "GOOGLE_SYMMETRIC_ENCRYPTION"
    protection_level = "SOFTWARE"
  }

  # Destroying a key schedules its versions for destruction after a delay
  # rather than deleting them. Allow it, since these keys protect demo data.
  lifecycle {
    prevent_destroy = false
  }
}

# Secret Manager encrypts with CMEK as its own service agent, not as the caller.
# The agent has to exist before it can be granted anything, and it is created
# lazily, so materialize it explicitly.
resource "google_project_service_identity" "secretmanager" {
  provider = google-beta

  project = var.project_id
  service = "secretmanager.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "secretmanager_agent" {
  crypto_key_id = google_kms_crypto_key.secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.secretmanager.email}"
}

# Artifact Registry encrypts with the same key, so it needs the same grant
# through its own service agent.
resource "google_project_service_identity" "artifactregistry" {
  provider = google-beta

  project = var.project_id
  service = "artifactregistry.googleapis.com"
}

resource "google_kms_crypto_key_iam_member" "artifactregistry_agent" {
  crypto_key_id = google_kms_crypto_key.secrets.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${google_project_service_identity.artifactregistry.email}"
}

resource "google_secret_manager_secret" "demo" {
  project   = var.project_id
  secret_id = "demo-api-key"
  labels    = var.labels

  # CMEK requires user-managed replication. Automatic replication cannot take a
  # customer key, because the key is regional and automatic replication is not.
  replication {
    user_managed {
      replicas {
        location = var.region

        customer_managed_encryption {
          kms_key_name = google_kms_crypto_key.secrets.id
        }
      }
    }
  }

  depends_on = [google_kms_crypto_key_iam_member.secretmanager_agent]
}

# Placeholder value. The point of the demo is the access path, not the payload.
resource "google_secret_manager_secret_version" "demo" {
  secret      = google_secret_manager_secret.demo.id
  secret_data = "not-a-real-secret-${var.pool_suffix}"
}

# Direct resource access again: the federated principal reads the secret with no
# service account in the path.
resource "google_secret_manager_secret_iam_member" "gh_read" {
  project   = google_secret_manager_secret.demo.project
  secret_id = google_secret_manager_secret.demo.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.gh_repo_principal
}
