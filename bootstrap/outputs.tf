output "folder_id" {
  description = "Numeric ID of the platform folder."
  value       = google_folder.platform.folder_id
}

output "bootstrap_project_id" {
  description = "Project holding Terraform state. Federated CI has no access here."
  value       = google_project.bootstrap.project_id
}

output "workload_project_id" {
  description = "Project holding every resource federated identities can reach."
  value       = google_project.workload.project_id
}

output "workload_project_number" {
  description = "Numeric project number. Workload identity pool resource names use the number, not the ID."
  value       = google_project.workload.number
}

output "state_bucket" {
  description = "Terraform state bucket."
  value       = google_storage_bucket.state.name
}

output "backend_hcl" {
  description = "Paste into terraform/backend.hcl, then run: terraform init -backend-config=backend.hcl"
  value       = <<-EOT
    bucket = "${google_storage_bucket.state.name}"
    prefix = "wif/dev"
  EOT
}

output "tfvars_snippet" {
  description = "Values the root module needs, ready to paste into terraform/terraform.tfvars."
  # Only the variables the root module declares. An extra key here would make
  # every later plan emit an undeclared-variable warning.
  value = <<-EOT
    project_id     = "${google_project.workload.project_id}"
    project_number = "${google_project.workload.number}"
  EOT
}
