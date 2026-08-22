# Manages the Cloud Run service that executes the application container.

# The imported service keeps the current immutable image, dedicated runtime
# identity, secret references, scaling limits, traffic policy, and HTTP probes.

resource "google_cloud_run_v2_service" "application" {
  project  = var.project_id
  name     = var.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # The live service must not be removable by an accidental terraform destroy.
  # A disposable target must explicitly disable this guard before testing destroy.
  deletion_protection = true

  scaling {
    min_instance_count = 0
    max_instance_count = 1
  }

  template {
    service_account                  = google_service_account.runtime.email
    timeout                          = "300s"
    max_instance_request_concurrency = 20

    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.application.repository_id}/${var.service_name}:${var.image_tag}"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }

        cpu_idle          = true
        startup_cpu_boost = true
      }

      env {
        name = "SPRING_DATASOURCE_URL"

        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.application["database_url"].secret_id
            version = "2"
          }
        }
      }

      env {
        name = "SPRING_DATASOURCE_USERNAME"

        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.application["database_username"].secret_id
            version = "2"
          }
        }
      }

      env {
        name = "SPRING_DATASOURCE_PASSWORD"

        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.application["database_password"].secret_id
            version = "2"
          }
        }
      }

      startup_probe {
        initial_delay_seconds = 0
        period_seconds        = 10
        timeout_seconds       = 5
        failure_threshold     = 24

        http_get {
          path = "/actuator/health/readiness"
          port = 8080
        }
      }

      readiness_probe {
        period_seconds    = 10
        timeout_seconds   = 5
        failure_threshold = 3

        http_get {
          path = "/actuator/health/readiness"
          port = 8080
        }
      }

      liveness_probe {
        initial_delay_seconds = 10
        period_seconds        = 30
        timeout_seconds       = 5
        failure_threshold     = 3

        http_get {
          path = "/actuator/health/liveness"
          port = 8080
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  # Secret containers and the runtime identity create implicit dependencies,
  # but the IAM grants must also exist before Cloud Run starts the revision.
  depends_on = [google_secret_manager_secret_iam_member.runtime_accessor]

  # These fields only record which deployment client last touched the service;
  # they are operational provenance, not desired application configuration.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
    ]
  }
}

# Makes the Cloud Run application callable without Google authentication.

# This additive member resource manages only the existing public invoker grant.
# It does not replace the service's complete IAM policy or alter other members.

resource "google_cloud_run_v2_service_iam_member" "public_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.application.location
  name     = google_cloud_run_v2_service.application.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
