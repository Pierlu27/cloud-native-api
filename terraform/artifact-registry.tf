# Manages the Docker repository that stores the application images.

# The current project repository is adopted with terraform import. The same
# declaration creates an equivalent repository when used with an empty state
# against a new target project.

resource "google_artifact_registry_repository" "application" {
  project       = var.project_id
  location      = var.region
  repository_id = var.repository_name
  description   = "Docker images for ${var.service_name}"
  format        = "DOCKER"
  mode          = "STANDARD_REPOSITORY"
}

# Allows the publisher service account to upload images to this repository.

# Repository-level scope avoids granting write access to every Artifact
# Registry repository in the project.

resource "google_artifact_registry_repository_iam_member" "publisher_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.application.location
  repository = google_artifact_registry_repository.application.repository_id
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.publisher.email}"
}
