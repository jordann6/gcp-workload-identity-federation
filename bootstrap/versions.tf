terraform {
  required_version = ">= 1.9"

  # Bootstrap keeps local state on purpose. It creates the bucket that every
  # other layer stores state in, so it cannot store its own state there without
  # a chicken-and-egg problem. The state file is gitignored.
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.12"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  billing_project       = null
  user_project_override = false
}
