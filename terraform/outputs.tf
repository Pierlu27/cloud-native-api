# Exposes the public HTTPS endpoint assigned to the Cloud Run service.

output "cloud_run_service_url" {
  description = "Public HTTPS URL of the Cloud Run application service."
  value       = google_cloud_run_v2_service.application.uri
}

# Exposes the provider-assigned Artifact Registry repository resource name.

output "artifact_registry_repository_name" {
  description = "Name of the Artifact Registry Docker repository."
  value       = google_artifact_registry_repository.application.name
}

# Exposes the identity that the Phase 9 GitHub Actions deployment job impersonates.

output "deployer_service_account_email" {
  description = "Email of the dedicated GitHub Actions Cloud Run deployer."
  value       = google_service_account.deployer.email
}

# Exposes the public endpoint assigned to each Phase 10 Cloud Run service.

output "environment_cloud_run_service_urls" {
  description = "Public Cloud Run service URL keyed by environment."
  value = {
    for environment_name, service in google_cloud_run_v2_service.environment :
    environment_name => service.uri
  }
}

# Exposes the revision currently reported as ready for each environment.

output "environment_cloud_run_latest_ready_revisions" {
  description = "Latest ready Cloud Run revision name keyed by environment."
  value = {
    for environment_name, service in google_cloud_run_v2_service.environment :
    environment_name => service.latest_ready_revision
  }
}

# Exposes the runtime identity assigned to each environment service.

output "environment_runtime_service_account_emails" {
  description = "Cloud Run runtime service account email keyed by environment."
  value = {
    for environment_name, runtime in google_service_account.environment_runtime :
    environment_name => runtime.email
  }
}
