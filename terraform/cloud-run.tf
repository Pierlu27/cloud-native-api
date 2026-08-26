# Creates one Cloud Run service that executes the application container for
# each environment. Both services share the same image and operational
# baseline, while their names, runtime identities, database secrets, and
# deletion protection are selected independently from the environment model.

resource "google_cloud_run_v2_service" "environment" {
  for_each = local.environments

  project  = var.project_id
  name     = each.value.service_name
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  # Production requires an explicit preliminary apply before destruction;
  # development remains disposable for controlled learning exercises.
  deletion_protection = each.value.cloud_run_deletion_protection

  scaling {
    min_instance_count = 0
    max_instance_count = 1
  }

  template {
    service_account                  = google_service_account.environment_runtime[each.key].email
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
            secret  = google_secret_manager_secret.environment["${each.key}.database_url"].secret_id
            version = each.value.database_secret_versions.database_url
          }
        }
      }

      env {
        name = "SPRING_DATASOURCE_USERNAME"

        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.environment["${each.key}.database_username"].secret_id
            version = each.value.database_secret_versions.database_username
          }
        }
      }

      env {
        name = "SPRING_DATASOURCE_PASSWORD"

        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.environment["${each.key}.database_password"].secret_id
            version = each.value.database_secret_versions.database_password
          }
        }
      }

      # Materialize the temporary fault-injection switch only in development
      # and only while explicitly requested. With the default false value the
      # environment variable is absent from both Cloud Run service templates.
      dynamic "env" {
        for_each = each.key == "development" && var.enable_development_test_error ? [true] : []

        content {
          name  = "OBSERVABILITY_TEST_ERROR_ENABLED"
          value = "true"
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

  # Secret containers and runtime identities create implicit dependencies, but
  # their IAM grants must also exist before Cloud Run starts a revision.
  depends_on = [google_secret_manager_secret_iam_member.environment_runtime_accessor]

  # Terraform owns the service structure, while the delivery workflow owns
  # subsequent images, revisions, traceability labels, and traffic. Client and
  # Google provisioning labels are operational provenance, not desired-state
  # settings; unrelated template labels remain drift-detected.
  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].containers[0].image,
      template[0].labels["commit-sha"],
      template[0].labels["goog-terraform-provisioned"],
      template[0].labels["managed-by"],
      template[0].revision,
      traffic,
    ]
  }
}

# Makes both environment-specific Cloud Run services publicly callable.

# Each additive member resource manages only the public invoker grant instead
# of replacing the service's complete IAM policy. Public invocation exposes
# application endpoints but grants no Cloud Run administration or secret access.

resource "google_cloud_run_v2_service_iam_member" "environment_public_invoker" {
  for_each = google_cloud_run_v2_service.environment

  project  = var.project_id
  location = each.value.location
  name     = each.value.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}
