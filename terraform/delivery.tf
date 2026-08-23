# Creates the identity used by GitHub Actions to deploy Cloud Run revisions.

# Publishing an image, deploying it, and running it are separate responsibilities,
# so the deployer does not replace the existing publisher or runtime identities.

resource "google_service_account" "deployer" {
  project      = var.project_id
  account_id   = var.deployer_service_account_id
  display_name = "GitHub Actions Cloud Run deployer"
  description  = "Identity used by GitHub Actions to deploy and promote Cloud Run revisions."
}

# Allows the trusted main-branch GitHub identity to impersonate the deployer.

# The existing WIF provider still validates the repository and branch claims;
# this additive binding grants impersonation of only the deployment identity.

resource "google_service_account_iam_member" "github_deployer_impersonation" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}/attribute.repository/${var.github_repository}"
}

# Allows the deployer to update this Cloud Run service and its traffic.

# Service-level scope avoids granting deployment access to every Cloud Run
# service in the project.

resource "google_cloud_run_v2_service_iam_member" "deployer" {
  project  = var.project_id
  location = google_cloud_run_v2_service.application.location
  name     = google_cloud_run_v2_service.application.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

# Allows the deployer to resolve the immutable image selected for deployment.

# Repository-level read access is sufficient; the publisher remains the only
# GitHub Actions identity with write access to application images.

resource "google_artifact_registry_repository_iam_member" "deployer_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.application.location
  repository = google_artifact_registry_repository.application.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

# Allows the deployer to attach the existing runtime identity to new revisions.

# Service Account User supplies iam.serviceAccounts.actAs; it does not let the
# deployer inherit the runtime account's Secret Manager permissions.

resource "google_service_account_iam_member" "deployer_runtime_user" {
  service_account_id = google_service_account.runtime.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}
