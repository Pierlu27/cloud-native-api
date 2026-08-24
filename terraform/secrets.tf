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

# Creates one empty Secret Manager container for every environment and
# datasource value. Payload versions remain an out-of-band operation so that
# database credentials never enter Terraform configuration or state.

resource "google_secret_manager_secret" "environment" {
  for_each = local.environment_database_secrets

  project   = var.project_id
  secret_id = each.value.secret_id

  deletion_protection = local.environments[each.value.environment].secret_deletion_protection

  labels = {
    environment  = each.value.environment
    "managed-by" = "terraform"
  }

  replication {
    auto {}
  }

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

# Grants each environment runtime access only to that environment's secrets.

# The key shared with local.environment_database_secrets identifies the owning
# environment, which is then used to select the matching runtime identity.

resource "google_secret_manager_secret_iam_member" "environment_runtime_accessor" {
  for_each = google_secret_manager_secret.environment

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.environment_runtime[local.environment_database_secrets[each.key].environment].email}"
}
