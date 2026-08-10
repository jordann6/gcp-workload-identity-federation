variable "org_id" {
  description = "Numeric GCP organization ID that owns the platform folder."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{10,14}$", var.org_id))
    error_message = "org_id must be the numeric organization ID, not the domain name."
  }
}

variable "billing_account" {
  description = "Billing account ID in XXXXXX-XXXXXX-XXXXXX form."
  type        = string

  validation {
    condition     = can(regex("^[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$", var.billing_account))
    error_message = "billing_account must look like 0X0X0X-0X0X0X-0X0X0X."
  }
}

variable "folder_name" {
  description = "Display name of the folder that holds the platform projects. The landing zone adopts this folder later rather than replacing it."
  type        = string
  default     = "platform"
}

variable "name_prefix" {
  description = "Prefix for generated project IDs. Keep it short, project IDs cap at 30 characters."
  type        = string
  default     = "jn-wif"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,12}$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, digits, and hyphens, 3 to 13 characters, starting with a letter."
  }
}

variable "region" {
  description = "Default region. Also the location of the Cloud KMS key ring, which cannot be moved after creation."
  type        = string
  default     = "us-central1"
}

variable "state_bucket_location" {
  description = "Location for the Terraform state bucket."
  type        = string
  default     = "US"
}

variable "force_destroy_state" {
  description = "Allow `terraform destroy` to delete the state bucket even when it holds objects. Leave false in normal use; set true only for the final teardown of the whole project."
  type        = bool
  default     = false
}

variable "labels" {
  description = "Labels applied to both projects."
  type        = map(string)
  default = {
    managed-by = "terraform"
    project    = "gcp-wif"
  }
}
