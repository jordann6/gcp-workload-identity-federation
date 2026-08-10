variable "project_id" {
  description = "Workload project ID, from the bootstrap layer output."
  type        = string
}

variable "project_number" {
  description = "Workload project number. Pool resource names use the number, not the ID."
  type        = string
}

variable "region" {
  description = "Region for regional resources. The KMS key ring location is fixed at creation and cannot be changed."
  type        = string
  default     = "us-central1"
}

variable "pool_suffix" {
  description = <<-EOT
    Suffix appended to workload identity pool IDs.

    A deleted pool is soft-deleted for 30 days and its ID cannot be reused in
    that window. Bumping this suffix lets a rebuild proceed without waiting.
  EOT
  type        = string
  default     = "v1"
}

variable "github_owner" {
  description = "GitHub account or org that owns the repository allowed to federate."
  type        = string
  default     = "jordann6"
}

variable "github_repo" {
  description = "Repository allowed to federate, in owner/name form. This value is enforced in the provider attribute condition, not merely mapped."
  type        = string
  default     = "jordann6/gcp-workload-identity-federation"

  validation {
    condition     = can(regex("^[^/]+/[^/]+$", var.github_repo))
    error_message = "github_repo must be in owner/name form."
  }
}

variable "github_deploy_ref" {
  description = "Git ref allowed to use the deploy identity. Pull requests from forks carry a different ref, so pinning this stops a fork PR from minting a deploy token."
  type        = string
  default     = "refs/heads/main"
}

variable "enable_aws_leg" {
  description = <<-EOT
    Build the two cross-cloud paths (AWS to GCP, and GCP to AWS).

    Requires AWS credentials in the environment at apply time. Leave false to
    build the GitHub paths only.
  EOT
  type        = bool
  default     = false
}

variable "aws_account_id" {
  description = "AWS account ID trusted by the AWS-to-GCP pool. Required when enable_aws_leg is true."
  type        = string
  default     = ""

  validation {
    condition     = var.aws_account_id == "" || can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be a 12-digit account ID."
  }
}

variable "aws_federated_role_name" {
  description = "Name of the AWS IAM role that the GCP service account is allowed to assume."
  type        = string
  default     = "gcp-federated-reader"
}

variable "aws_region" {
  description = "Region for the AWS provider. Only used when enable_aws_leg is true."
  type        = string
  default     = "us-east-2"
}

variable "labels" {
  description = "Labels applied to labelable resources."
  type        = map(string)
  default = {
    managed-by = "terraform"
    project    = "gcp-wif"
  }
}
