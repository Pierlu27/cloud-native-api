# Counts server-error request logs emitted by the Cloud Run application.

# This passive counter observes real traffic only. It creates no synthetic
# requests and defines no custom labels, keeping cardinality and cost minimal.

resource "google_logging_metric" "cloud_run_http_5xx" {
  project     = var.project_id
  name        = "${var.service_name}-http-5xx"
  description = "Counts HTTP 5xx responses from the development and production Cloud Run services."
  disabled    = false

  # Construct the multiline filter with explicit LF separators so that
  # Windows CRLF checkout settings do not create perpetual Terraform drift.
  filter = format("%s\n", join("\n", [
    "resource.type=\"cloud_run_revision\" AND",
    "resource.labels.service_name=~\"^${var.service_name}-(dev|prod)$\" AND",
    "log_id(\"run.googleapis.com/requests\") AND",
    "httpRequest.status>=500 AND",
    "httpRequest.status<600",
  ]))

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
    content   = "A Cloud Native API Cloud Run service returned at least one HTTP 5xx response. Use the service_name resource label to identify the affected environment, then review its request and application logs."
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

# Counts structured application log entries emitted at ERROR severity or above.

# Request IDs, paths, messages, and exceptions deliberately remain searchable
# log fields rather than metric labels, preventing high-cardinality time series.

resource "google_logging_metric" "application_error_entries" {
  project     = var.project_id
  name        = "${var.service_name}-application-errors"
  description = "Counts ERROR-level application log entries from the development and production Cloud Run services."
  disabled    = false

  # Spring writes its structured application logs to stdout. Cloud Logging
  # promotes their top-level severity field before this filter is evaluated.
  filter = format("%s\n", join("\n", [
    "resource.type=\"cloud_run_revision\" AND",
    "resource.labels.service_name=~\"^${var.service_name}-(dev|prod)$\" AND",
    "log_id(\"run.googleapis.com/stdout\") AND",
    "severity>=ERROR",
  ]))

  metric_descriptor {
    metric_kind  = "DELTA"
    value_type   = "INT64"
    unit         = "1"
    display_name = "Application ERROR log entries"
  }

  depends_on = [google_project_service.logging]
}

# Checks the complete public production path, including application readiness
# and database connectivity, without generating recurring development traffic.

resource "google_monitoring_uptime_check_config" "production_external_health" {
  project          = var.project_id
  display_name     = "Cloud Native API production external health"
  timeout          = "30s"
  period           = "900s"
  selected_regions = ["EUROPE", "USA"]
  checker_type     = "STATIC_IP_CHECKERS"

  http_check {
    request_method = "GET"
    path           = "/actuator/health/external"
    port           = "443"
    use_ssl        = true
    validate_ssl   = true

    accepted_response_status_codes {
      status_class = "STATUS_CLASS_2XX"
    }
  }

  monitored_resource {
    type = "uptime_url"
    labels = {
      project_id = var.project_id
      host       = trimprefix(google_cloud_run_v2_service.environment["production"].uri, "https://")
    }
  }

  content_matchers {
    content = "\"UP\""
    matcher = "MATCHES_JSON_PATH"

    json_path_matcher {
      json_path    = "$.status"
      json_matcher = "EXACT_MATCH"
    }
  }

  depends_on = [google_project_service.monitoring]
}

# Creates the human destination used by the Phase 11 error-rate alert.

# The real address is supplied only through the ignored local tfvars file. It is
# marked sensitive for CLI redaction but necessarily remains in Terraform state.

resource "google_monitoring_notification_channel" "alert_email" {
  project      = var.project_id
  display_name = "Cloud Native API alert email"
  description  = "Email destination for Cloud Native API observability incidents."
  type         = "email"
  enabled      = true

  labels = {
    email_address = var.alert_notification_email
  }

  force_delete = false

  depends_on = [google_project_service.monitoring]
}

# Opens one incident per affected environment when native Cloud Run HTTP 5xx
# requests exceed 20 percent of that service's traffic in a five-minute window.

resource "google_monitoring_alert_policy" "cloud_run_http_5xx_error_rate" {
  project               = var.project_id
  display_name          = "Cloud Run HTTP 5xx error rate above 20%"
  combiner              = "OR"
  enabled               = true
  notification_channels = [google_monitoring_notification_channel.alert_email.name]

  documentation {
    content   = "A Cloud Native API environment exceeded a 20% HTTP 5xx error rate over five minutes. Use the service_name resource label to identify development or production, then correlate the native request metric with structured application logs by request_id."
    mime_type = "text/markdown"
  }

  conditions {
    display_name = "HTTP 5xx responses exceed 20% in 5 minutes"

    condition_threshold {
      filter                  = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = monitoring.regex.full_match(\"^${var.service_name}-(dev|prod)$\") AND metric.type = \"run.googleapis.com/request_count\" AND metric.labels.response_code_class = \"5xx\""
      denominator_filter      = "resource.type = \"cloud_run_revision\" AND resource.labels.service_name = monitoring.regex.full_match(\"^${var.service_name}-(dev|prod)$\") AND metric.type = \"run.googleapis.com/request_count\""
      comparison              = "COMPARISON_GT"
      threshold_value         = 0.20
      duration                = "60s"
      evaluation_missing_data = "EVALUATION_MISSING_DATA_INACTIVE"

      aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.\"service_name\""]
      }

      denominator_aggregations {
        alignment_period     = "300s"
        per_series_aligner   = "ALIGN_SUM"
        cross_series_reducer = "REDUCE_SUM"
        group_by_fields      = ["resource.label.\"service_name\""]
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
