# Cross-cloud federation, both directions.
#
# Gated behind enable_aws_leg because it needs AWS credentials at apply time.
#
#   Path 3: AWS to GCP. An AWS IAM role reaches GCP resources with no GCP key.
#           GCP verifies the caller by validating a signed GetCallerIdentity
#           request against AWS STS, which is why this provider type takes an
#           account ID rather than an issuer URL.
#
#   Path 4: GCP to AWS. A GCP service account reaches AWS with no AWS key.
#           AWS treats accounts.google.com as a built-in web identity provider,
#           so no IAM OIDC provider resource is created. Trust is pinned to the
#           service account's numeric unique ID through the aud claim.

# ---------------------------------------------------------------------------
# Path 3: AWS to GCP
# ---------------------------------------------------------------------------

resource "google_iam_workload_identity_pool" "aws" {
  count = var.enable_aws_leg ? 1 : 0

  project                   = var.project_id
  workload_identity_pool_id = "aws-${var.pool_suffix}"
  display_name              = "AWS accounts"
  description               = "Federates IAM roles from one AWS account."
}

resource "google_iam_workload_identity_pool_provider" "aws" {
  count = var.enable_aws_leg ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.aws[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "aws-sts"
  display_name                       = "AWS STS"

  # The assumed-role ARN carries a session name that changes every call, so the
  # role ARN has to be reconstructed from its parts to be usable as a stable
  # attribute to bind against.
  attribute_mapping = {
    "google.subject"     = "assertion.arn"
    "attribute.aws_role" = "assertion.arn.extract('assumed-role/{role}/')"
    "attribute.account"  = "assertion.account"
  }

  # Same principle as the GitHub provider: the account is enforced by the aws
  # block, and the specific role is enforced here.
  attribute_condition = "attribute.aws_role == \"${var.aws_federated_role_name}\""

  aws {
    account_id = var.aws_account_id
  }
}

resource "google_storage_bucket_iam_member" "aws_read" {
  count = var.enable_aws_leg ? 1 : 0

  bucket = google_storage_bucket.artifacts.name
  role   = "roles/storage.objectViewer"
  member = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.aws[0].name}/attribute.aws_role/${var.aws_federated_role_name}"
}

# ---------------------------------------------------------------------------
# Path 4: GCP to AWS
# ---------------------------------------------------------------------------

resource "google_service_account" "aws_caller" {
  count = var.enable_aws_leg ? 1 : 0

  project      = var.project_id
  account_id   = "aws-caller"
  display_name = "Calls AWS via web identity federation"
  description  = "Its OIDC ID token is exchanged for AWS credentials. Holds no AWS key."
}

data "aws_caller_identity" "current" {
  count = var.enable_aws_leg ? 1 : 0
}

resource "aws_iam_role" "gcp_federated" {
  count = var.enable_aws_leg ? 1 : 0

  name        = var.aws_federated_role_name
  description = "Assumed by a GCP service account through web identity federation. No long-lived credential exists on either side."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        # Built into AWS. No aws_iam_openid_connect_provider resource needed.
        Federated = "accounts.google.com"
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # The service account's numeric unique ID, not its email. The email is
          # reusable after deletion; the unique ID is not, which is why the
          # audience check has to pin the ID.
          "accounts.google.com:aud" = google_service_account.aws_caller[0].unique_id
        }
      }
    }]
  })

  tags = var.labels
}

resource "aws_iam_role_policy" "gcp_federated_read" {
  count = var.enable_aws_leg ? 1 : 0

  name = "read-caller-identity"
  role = aws_iam_role.gcp_federated[0].id

  # Deliberately minimal. The demo proves the credential exchange works, and
  # sts:GetCallerIdentity is enough to prove it while granting nothing.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sts:GetCallerIdentity"]
      Resource = "*"
    }]
  })
}
