# The provider authenticates through Application Default Credentials (ADC).
# No service-account JSON key is stored in this repository or passed as input.

provider "google" {
  project = var.project_id
  region  = var.region
}
