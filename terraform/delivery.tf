# Allows each trusted GitHub branch to impersonate only its environment deployer.

# Publishing an image, deploying it, and running it are separate
# responsibilities. The WIF provider validates repository and branch claims;
# these additive member bindings then select only the matching deployment
# identity, preventing cross-environment deploys.

resource "google_service_account_iam_member" "github_environment_deployer_impersonation" {
  for_each = local.environments

  service_account_id = google_service_account.environment_deployer[each.key].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}/attribute.environment/${each.key}"
}

# Allows each environment deployer to update only its matching Cloud Run service.

# These additive, service-level bindings preserve the dev/prod boundary instead
# of granting either deployer Cloud Run permissions across the entire project.

resource "google_cloud_run_v2_service_iam_member" "environment_deployer" {
  for_each = google_cloud_run_v2_service.environment

  project  = var.project_id
  location = each.value.location
  name     = each.value.name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.environment_deployer[each.key].email}"
}

# Allows both environment deployers to resolve images from the shared repository.

# Repository-level reader access supports deployment without permission to
# publish, overwrite, or delete images; the publisher remains the only GitHub
# Actions identity with write access to application images.

resource "google_artifact_registry_repository_iam_member" "environment_deployer_reader" {
  for_each = google_service_account.environment_deployer

  project    = var.project_id
  location   = google_artifact_registry_repository.application.location
  repository = google_artifact_registry_repository.application.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${each.value.email}"
}

# Allows each environment deployer to attach only its matching runtime identity.

# The shared for_each key pairs development with development and production
# with production, preventing a deployer from selecting the other runtime.
# Service Account User supplies iam.serviceAccounts.actAs; it does not let a
# deployer inherit the runtime account's Secret Manager permissions.

resource "google_service_account_iam_member" "environment_deployer_runtime_user" {
  for_each = local.environments

  service_account_id = google_service_account.environment_runtime[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.environment_deployer[each.key].email}"
}

# Allows the local Jenkins deployer to update only the development service.

# The binding lives on the existing development Cloud Run resource rather than
# at project level, so the same identity receives no authority over production.

resource "google_cloud_run_v2_service_iam_member" "jenkins_deployer" {
  project  = var.project_id
  location = google_cloud_run_v2_service.environment["development"].location
  name     = google_cloud_run_v2_service.environment["development"].name
  role     = "roles/run.developer"
  member   = "serviceAccount:${google_service_account.jenkins_deployer.email}"
}

# Allows the local Jenkins deployer to resolve the development image by SHA.

# Reader access is scoped to the shared application repository. It cannot push,
# overwrite, or delete the images owned by either publishing pipeline.

resource "google_artifact_registry_repository_iam_member" "jenkins_deployer_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.application.location
  repository = google_artifact_registry_repository.application.repository_id
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.jenkins_deployer.email}"
}

# Allows the local Jenkins deployer to attach only the development runtime.

# Service Account User supplies iam.serviceAccounts.actAs. It lets Jenkins tell
# Cloud Run which identity the container must run as without granting Jenkins
# the runtime account's Secret Manager permissions.

resource "google_service_account_iam_member" "jenkins_deployer_runtime_user" {
  service_account_id = google_service_account.environment_runtime["development"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.jenkins_deployer.email}"
}
