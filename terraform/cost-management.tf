# Creates one monthly budget for costs attributed to this project alone.

# A budget is an alerting boundary, not a spending cap. Current-spend threshold
# emails can arrive after billing ingestion delay and never disable services.

resource "google_billing_budget" "project" {
  provider        = google.billing
  billing_account = var.billing_account_id
  display_name    = "Cloud Native API monthly budget"
  deletion_policy = "DELETE"

  budget_filter {
    projects               = ["projects/${data.google_project.current.number}"]
    calendar_period        = "MONTH"
    credit_types_treatment = "INCLUDE_ALL_CREDITS"
  }

  amount {
    specified_amount {
      currency_code = var.billing_budget_currency
      units         = tostring(var.billing_budget_amount)
    }
  }

  threshold_rules {
    threshold_percent = 0.20
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.50
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 0.90
    spend_basis       = "CURRENT_SPEND"
  }

  threshold_rules {
    threshold_percent = 1.00
    spend_basis       = "CURRENT_SPEND"
  }

  all_updates_rule {
    monitoring_notification_channels = [google_monitoring_notification_channel.alert_email.name]
    disable_default_iam_recipients   = true
  }

  depends_on = [google_project_service.billing_budgets]
}
