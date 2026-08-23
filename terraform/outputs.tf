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
