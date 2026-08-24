# Creates one Secret Manager container for every environment and datasource
# value. Terraform manages containers and metadata only; payload versions are
# populated out of band so credentials never enter configuration or state.

resource "google_secret_manager_secret" "environment" {
  for_each = local.environment_database_secrets

  project   = var.project_id
  secret_id = each.value.secret_id

  deletion_protection = local.environments[each.value.environment].secret_deletion_protection

  labels = {
    environment  = each.value.environment
    "managed-by" = "terraform"
  }

  # Google manages replica placement because the project has no regional data
  # residency requirement for these application secrets.
  replication {
    auto {}
  }

  # Enabling an API does not create an implicit dependency through an attribute,
  # so the required creation order is declared explicitly.
  depends_on = [google_project_service.secret_manager]
}

# Grants each environment runtime access only to that environment's secrets.

# A member-level IAM resource adds one grant without replacing the complete
# secret policy. The shared key identifies the owning environment and selects
# its runtime, providing resource-level access instead of project-wide access.

resource "google_secret_manager_secret_iam_member" "environment_runtime_accessor" {
  for_each = google_secret_manager_secret.environment

  project   = var.project_id
  secret_id = each.value.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.environment_runtime[local.environment_database_secrets[each.key].environment].email}"
}
