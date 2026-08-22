# Creates the empty Secret Manager containers for the application secrets.

# Terraform manages only the secret containers and their metadata. Secret
# versions (the actual database values) are populated out of band with gcloud,
# so their payloads never enter Terraform configuration or state.

resource "google_secret_manager_secret" "application" {
  for_each = local.application_secret_ids

  project   = var.project_id
  secret_id = each.value

  # Google manages replica placement because Phase 8 has no regional data
  # residency requirement for these secrets.

  replication {
    auto {}
  }

  # Unlike references to another resource attribute, enabling an API does not
  # create an implicit dependency, so the ordering is declared explicitly.

  depends_on = [google_project_service.secret_manager]
}

# Grants the runtime service account permission to read each application secret.

# A member-level IAM resource adds one grant without replacing the secret's
# complete IAM policy. The runtime identity receives least-privilege access to
# each application secret individually, not to every secret in the project.

resource "google_secret_manager_secret_iam_member" "runtime_accessor" {
  for_each = google_secret_manager_secret.application

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.runtime.email}"
}
