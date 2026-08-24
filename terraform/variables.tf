variable "project_id" {
  description = "GCP project ID that owns the infrastructure."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid 6-30 character GCP project ID."
  }
}

variable "region" {
  description = "GCP region used by regional resources."
  type        = string

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must use a GCP region format such as europe-west8."
  }
}

variable "service_name" {
  description = "Base application name used by the historical service and to derive environment-specific resource names."
  type        = string

  validation {
    condition     = length(var.service_name) <= 49 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.service_name))
    error_message = "service_name must start with a letter, end with a letter or digit, and contain at most 49 lowercase letters, digits, or hyphens."
  }
}

variable "repository_name" {
  description = "Artifact Registry repository ID."
  type        = string

  validation {
    condition     = length(var.repository_name) >= 4 && length(var.repository_name) <= 63 && can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.repository_name))
    error_message = "repository_name must contain 4-63 lowercase letters, digits, or hyphens and must start with a letter."
  }
}

variable "runtime_service_account_id" {
  description = "Account ID of the dedicated Cloud Run runtime service account."
  type        = string
  default     = "cloud-native-api-runtime"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.runtime_service_account_id))
    error_message = "runtime_service_account_id must be 6-30 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, or hyphens."
  }
}

variable "publisher_service_account_id" {
  description = "Account ID of the service account impersonated by GitHub Actions to publish images."
  type        = string
  default     = "github-artifact-publisher"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.publisher_service_account_id))
    error_message = "publisher_service_account_id must be 6-30 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, or hyphens."
  }
}

variable "deployer_service_account_id" {
  description = "Account ID of the service account impersonated by GitHub Actions to deploy Cloud Run revisions."
  type        = string
  default     = "github-cloud-run-deployer"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.deployer_service_account_id))
    error_message = "deployer_service_account_id must be 6-30 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, or hyphens."
  }
}

variable "workload_identity_pool_id" {
  description = "ID of the Workload Identity Pool used by GitHub Actions."
  type        = string
  default     = "github-actions"

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.workload_identity_pool_id)) &&
      length(var.workload_identity_pool_id) >= 4 &&
      length(var.workload_identity_pool_id) <= 32 &&
      !startswith(var.workload_identity_pool_id, "gcp-")
    )
    error_message = "workload_identity_pool_id must be 4-32 lowercase letters, digits, or hyphens; start with a letter, end with a letter or digit, and not use the reserved gcp- prefix."
  }
}

variable "workload_identity_provider_id" {
  description = "ID of the OIDC provider that validates GitHub Actions tokens."
  type        = string
  default     = "github"

  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.workload_identity_provider_id)) &&
      length(var.workload_identity_provider_id) >= 4 &&
      length(var.workload_identity_provider_id) <= 32 &&
      !startswith(var.workload_identity_provider_id, "gcp-")
    )
    error_message = "workload_identity_provider_id must be 4-32 lowercase letters, digits, or hyphens; start with a letter, end with a letter or digit, and not use the reserved gcp- prefix."
  }
}

variable "github_repository" {
  description = "GitHub repository allowed to federate, in owner/repository format."
  type        = string
  default     = "Pierlu27/cloud-native-api"

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must use the owner/repository format."
  }
}

variable "github_branch" {
  description = "GitHub branch allowed to federate through the OIDC provider."
  type        = string
  default     = "main"

  validation {
    condition     = length(trimspace(var.github_branch)) > 0 && !can(regex("\\s", var.github_branch))
    error_message = "github_branch must be non-empty and contain no whitespace."
  }
}

variable "image_tag" {
  description = "Immutable full Git commit SHA used as the container image tag."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag must be a full 40-character lowercase Git commit SHA; latest is not allowed."
  }
}
