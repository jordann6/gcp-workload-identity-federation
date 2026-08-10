output "workload_identity_provider" {
  description = "Full provider resource name. This is the workload_identity_provider input to google-github-actions/auth."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "github_repo_principal" {
  description = "Principal set matching any run from the allowed repository. Holds read access."
  value       = local.gh_repo_principal
}

output "github_deploy_principal" {
  description = "Principal set matching runs on the deploy ref only. Holds write access."
  value       = local.gh_deploy_principal
}

output "deployer_service_account" {
  description = "Service account used by the impersonation path. Supply as service_account to google-github-actions/auth to compare the two paths."
  value       = google_service_account.deployer.email
}

output "artifacts_bucket" {
  description = "Bucket reachable by federated principals with no service account in the path."
  value       = google_storage_bucket.artifacts.name
}

output "artifact_registry_repo" {
  description = "Container registry the deploy ref can push to."
  value       = google_artifact_registry_repository.images.id
}

output "demo_secret_id" {
  description = "CMEK-encrypted secret read by the federation demo."
  value       = google_secret_manager_secret.demo.secret_id
}

output "kms_key" {
  description = "Key protecting the secret. Disabling its version revokes read access to every secret version under it."
  value       = google_kms_crypto_key.secrets.id
}

output "aws_role_arn" {
  description = "AWS role assumable by the GCP service account. Empty when enable_aws_leg is false."
  value       = try(aws_iam_role.gcp_federated[0].arn, "")
}

output "aws_caller_service_account" {
  description = "GCP service account whose ID token is exchanged for AWS credentials. Empty when enable_aws_leg is false."
  value       = try(google_service_account.aws_caller[0].email, "")
}
