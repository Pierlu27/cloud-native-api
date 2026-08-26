variable "project_id" {
  description = "GCP project ID that owns the infrastructure."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid 6-30 character GCP project ID."
  }
}

variable "billing_account_id" {
  description = "Cloud Billing account ID that owns the project-scoped monthly budget."
  type        = string

  validation {
    condition     = can(regex("^[0-9A-F]{6}-[0-9A-F]{6}-[0-9A-F]{6}$", var.billing_account_id))
    error_message = "billing_account_id must use the 000000-000000-000000 format."
  }
}

variable "billing_budget_amount" {
  description = "Positive whole-unit monthly budget amount used for project cost alerts."
  type        = number
  default     = 5

  validation {
    condition     = var.billing_budget_amount > 0 && floor(var.billing_budget_amount) == var.billing_budget_amount
    error_message = "billing_budget_amount must be a positive whole number."
  }
}

variable "billing_budget_currency" {
  description = "ISO 4217 currency code used by the Cloud Billing account."
  type        = string
  default     = "EUR"

  validation {
    condition     = can(regex("^[A-Z]{3}$", var.billing_budget_currency))
    error_message = "billing_budget_currency must be a three-letter uppercase ISO 4217 code such as EUR."
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
  description = "Base application name used to derive shared and environment-specific resource names."
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

variable "publisher_service_account_id" {
  description = "Account ID of the service account impersonated by GitHub Actions to publish images."
  type        = string
  default     = "github-artifact-publisher"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.publisher_service_account_id))
    error_message = "publisher_service_account_id must be 6-30 characters, start with a lowercase letter, end with a lowercase letter or digit, and contain only lowercase letters, digits, or hyphens."
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

variable "image_tag" {
  description = "Immutable full Git commit SHA used as the container image tag."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{40}$", var.image_tag))
    error_message = "image_tag must be a full 40-character lowercase Git commit SHA; latest is not allowed."
  }
}

variable "alert_notification_email" {
  description = "Email address that receives Cloud Monitoring alert notifications; stored in local tfvars and Terraform state."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_notification_email))
    error_message = "alert_notification_email must be a valid email address."
  }
}

variable "enable_development_test_error" {
  description = "Temporarily registers the controlled observability error endpoint in development only."
  type        = bool
  default     = false
}
