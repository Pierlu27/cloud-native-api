# Defines the names of the application secrets.

# Reads the current project metadata without managing the project itself.

# Workload Identity Federation APIs represent their parent project with its
# immutable numeric identifier, so WIF resources consume the number read here.

data "google_project" "current" {
  project_id = var.project_id
}

# Stable logical keys keep the Terraform resource addresses unchanged even if
# a Google Cloud secret ID is renamed later.

locals {
  application_secret_ids = {
    database_url      = "${var.service_name}-database-url"
    database_username = "${var.service_name}-database-username"
    database_password = "${var.service_name}-database-password"
  }
}

# Enables the Secret Manager API in the Google Cloud project.

# A project API is shared infrastructure. Terraform enables Secret Manager but
# deliberately leaves the API enabled if this resource is destroyed or removed
# from the state, avoiding disruption to resources managed elsewhere.

resource "google_project_service" "secret_manager" {
  project = var.project_id
  service = "secretmanager.googleapis.com"

  disable_on_destroy = false
}

# Keeps the Cloud Logging API enabled for request and application log ingestion.

# Logging is shared project infrastructure, so removing this Terraform resource
# must not disable the API or interrupt telemetry collected from Cloud Run.

resource "google_project_service" "logging" {
  project = var.project_id
  service = "logging.googleapis.com"

  disable_on_destroy = false
}

# Keeps the Cloud Monitoring API enabled for metrics and alert evaluation.

# Monitoring is also shared infrastructure and remains enabled if this resource
# is destroyed or removed from the Terraform state.

resource "google_project_service" "monitoring" {
  project = var.project_id
  service = "monitoring.googleapis.com"

  disable_on_destroy = false
}

# Counts server-error request logs emitted by the Cloud Run application.

# This passive counter observes real traffic only. It creates no synthetic
# requests and defines no custom labels, keeping cardinality and cost minimal.

resource "google_logging_metric" "cloud_run_http_5xx" {
  project     = var.project_id
  name        = "${var.service_name}-http-5xx"
  description = "Counts HTTP 5xx responses from the ${var.service_name} Cloud Run service."
  disabled    = false

  filter = <<-EOT
    resource.type="cloud_run_revision" AND
    resource.labels.service_name="${var.service_name}" AND
    log_id("run.googleapis.com/requests") AND
    httpRequest.status>=500 AND
    httpRequest.status<600
  EOT

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Cloud Run HTTP 5xx responses"
  }

  depends_on = [google_project_service.logging]
}

# Opens a Monitoring incident when the application emits HTTP 5xx responses.

# The policy observes the passive log-based counter and intentionally defines no
# notification channels. Incidents remain visible in Monitoring without email,
# SMS, or synthetic traffic.

resource "google_monitoring_alert_policy" "cloud_run_http_5xx" {
  project      = var.project_id
  display_name = "Cloud Run HTTP 5xx detected"
  combiner     = "OR"
  enabled      = true

  documentation {
    content   = "The ${var.service_name} Cloud Run service returned at least one HTTP 5xx response. Review the Cloud Run request and application logs."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "At least one HTTP 5xx response in 5 minutes"

    condition_threshold {
      filter                  = "resource.type = \"cloud_run_revision\" AND metric.type = \"logging.googleapis.com/user/${google_logging_metric.cloud_run_http_5xx.name}\""
      comparison              = "COMPARISON_GT"
      threshold_value         = 0
      duration                = "60s"
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"

      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }

      trigger {
        count = 1
      }
    }
  }

  alert_strategy {
    auto_close = "1800s"
  }

  depends_on = [google_project_service.monitoring]
}

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

# Creates the dedicated service account used by Cloud Run at runtime.

# Cloud Run will use this dedicated runtime identity instead of the default
# Compute Engine service account, keeping application permissions isolated.

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = var.runtime_service_account_id
  display_name = "Cloud Native API runtime"
  description  = "Identity used by the Cloud Run service at runtime."
}

# Manages the identity impersonated by GitHub Actions to publish images.

# The current project service account is adopted with terraform import. Its
# Workload Identity Federation trust and Artifact Registry permissions are
# separate IAM resources and are managed independently.

resource "google_service_account" "publisher" {
  project      = var.project_id
  account_id   = var.publisher_service_account_id
  display_name = "GitHub Actions Artifact Registry publisher"
}

# Manages the namespace used to represent GitHub identities in Google Cloud.

# The pool alone grants no permissions and validates no tokens. Its OIDC
# provider and service-account impersonation binding are separate resources.

resource "google_iam_workload_identity_pool" "github_actions" {
  project                   = data.google_project.current.number
  workload_identity_pool_id = var.workload_identity_pool_id
  display_name              = "GitHub Actions"
  disabled                  = false
}

# Validates GitHub-issued OIDC tokens and maps their claims to Google attributes.

# The condition restricts federation to this repository's main branch. Passing
# the provider check still grants no Google Cloud permission by itself; the
# publisher impersonation binding is managed separately.

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = data.google_project.current.number
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_actions.workload_identity_pool_id
  workload_identity_pool_provider_id = var.workload_identity_provider_id
  display_name                       = "GitHub OIDC"
  disabled                           = false

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  attribute_condition = "assertion.repository == '${var.github_repository}' && assertion.ref == 'refs/heads/${var.github_branch}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Allows the trusted GitHub repository identity to impersonate the publisher.

# A member-level resource manages only this additive grant instead of replacing
# the service account's complete IAM policy.

resource "google_service_account_iam_member" "github_publisher_impersonation" {
  service_account_id = google_service_account.publisher.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github_actions.workload_identity_pool_id}/attribute.repository/${var.github_repository}"
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
