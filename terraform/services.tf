# Enables the Secret Manager API in the Google Cloud project.

# A project API is shared infrastructure. Terraform enables Secret Manager but
# deliberately leaves the API enabled if this resource is destroyed or removed
# from the state, avoiding disruption to resources managed elsewhere.

resource "google_project_service" "secret_manager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"

  disable_on_destroy = false
}

# Keeps the Cloud Logging API enabled for request and application log ingestion.

# Logging is shared project infrastructure, so removing this Terraform resource
# must not disable the API or interrupt telemetry collected from Cloud Run.

resource "google_project_service" "logging" {
  project = var.project_id
  service = "logging.googleapis.com"

  disable_on_destroy = false
}

# Keeps the Cloud Monitoring API enabled for metrics and alert evaluation.

# Monitoring is also shared infrastructure and remains enabled if this resource
# is destroyed or removed from the Terraform state.

resource "google_project_service" "monitoring" {
  project = var.project_id
  service = "monitoring.googleapis.com"

  disable_on_destroy = false
}
