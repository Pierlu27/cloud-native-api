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
