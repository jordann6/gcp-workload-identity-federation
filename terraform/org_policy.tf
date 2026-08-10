# Org policy.
#
# Every other file in this build avoids service account keys. These two make
# avoiding them non-optional: with both enforced, a key cannot be created or
# uploaded in this project even by an owner. That converts "we don't use keys"
# from a convention into a control, and it is the difference between the claim
# and the proof.
#
# Applied at the project level rather than the org so the rest of the
# organization is unaffected. The landing zone later hoists equivalents to a
# folder, which is the right altitude once more than one project exists.

resource "google_org_policy_policy" "disable_sa_key_creation" {
  name   = "projects/${var.project_id}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "disable_sa_key_upload" {
  name   = "projects/${var.project_id}/policies/iam.disableServiceAccountKeyUpload"
  parent = "projects/${var.project_id}"

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
