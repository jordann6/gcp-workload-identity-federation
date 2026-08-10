terraform {
  required_version = ">= 1.9"

  # Partial backend config. Values come from backend.hcl, which is gitignored
  # because the bucket name embeds a project ID:
  #   terraform init -backend-config=backend.hcl
  backend "gcs" {}

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.12"
    }
    # Needed only for google_project_service_identity, which materializes the
    # Secret Manager service agent so the KMS grant below can reference it.
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.12"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Only used when enable_aws_leg is true. Terraform still requires the provider
# block to be present and resolvable even when every resource using it is
# counted out, so the region falls back to a default rather than being required.
provider "aws" {
  region = var.aws_region
}
