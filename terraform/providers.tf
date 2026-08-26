# The provider authenticates through Application Default Credentials (ADC).
# No service-account JSON key is stored in this repository or passed as input.

provider "google" {
  project = var.project_id
  region  = var.region
}

# Uses the same user ADC identity with an explicit quota project only for Cloud
# Billing Budget API calls, leaving all existing infrastructure on the default
# provider behavior.

provider "google" {
  alias                 = "billing"
  project               = var.project_id
  region                = var.region
  billing_project       = var.project_id
  user_project_override = true
}
