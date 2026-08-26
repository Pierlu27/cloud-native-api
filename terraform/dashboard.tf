# Selects both Cloud Run environments while leaving their service_name label
# available for grouping into separate development and production time series.

locals {
  cloud_run_dashboard_resource_filter = "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=monitoring.regex.full_match(\"^${var.service_name}-(dev|prod)$\")"
  dashboard_service_group_by          = ["resource.label.\"service_name\""]
  production_uptime_resource_filter   = "resource.type=\"uptime_url\" AND metric.labels.check_id=\"${google_monitoring_uptime_check_config.production_external_health.uptime_check_id}\""
}

# Creates one shared view of the traffic, errors, resources, and external
# availability signals emitted by both application environments.

resource "google_monitoring_dashboard" "observability" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "Cloud Native API - Observability"

    mosaicLayout = {
      columns = 12

      tiles = [
        {
          width  = 6
          height = 4

          widget = {
            title = "Requests per 5 minutes"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"run.googleapis.com/request_count\""

                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_SUM"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = local.dashboard_service_group_by
                      }
                    }

                    unitOverride = "1"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "requests"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          xPos   = 6
          width  = 6
          height = 4

          widget = {
            title = "Native HTTP 5xx error rate"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilterRatio = {
                      numerator = {
                        filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"run.googleapis.com/request_count\" AND metric.labels.response_code_class=\"5xx\""

                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = local.dashboard_service_group_by
                        }
                      }

                      denominator = {
                        filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"run.googleapis.com/request_count\""

                        aggregation = {
                          alignmentPeriod    = "300s"
                          perSeriesAligner   = "ALIGN_SUM"
                          crossSeriesReducer = "REDUCE_SUM"
                          groupByFields      = local.dashboard_service_group_by
                        }
                      }
                    }

                    unitOverride = "10^2.%"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "error rate"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          yPos   = 4
          width  = 6
          height = 4

          widget = {
            title = "Request latency p50"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"run.googleapis.com/request_latencies\""

                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_SUM"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = local.dashboard_service_group_by
                      }

                      secondaryAggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_PERCENTILE_50"
                      }
                    }

                    unitOverride = "ms"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "milliseconds"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 4
          width  = 6
          height = 4

          widget = {
            title = "Request latency p95"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"run.googleapis.com/request_latencies\""

                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_SUM"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = local.dashboard_service_group_by
                      }

                      secondaryAggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_PERCENTILE_95"
                      }
                    }

                    unitOverride = "ms"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "milliseconds"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          yPos   = 8
          width  = 6
          height = 4

          widget = {
            title = "Phase 8 HTTP 5xx count"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.cloud_run_http_5xx.name}\""

                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_SUM"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = local.dashboard_service_group_by
                      }
                    }

                    unitOverride = "1"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "HTTP 5xx responses"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 8
          width  = 6
          height = 4

          widget = {
            title = "Application ERROR log entries"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.application_error_entries.name}\""

                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_SUM"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = local.dashboard_service_group_by
                      }
                    }

                    unitOverride = "1"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "ERROR log entries"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          yPos   = 12
          width  = 6
          height = 4

          widget = {
            title = "CPU utilization p95"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"run.googleapis.com/container/cpu/utilizations\""

                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_SUM"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = local.dashboard_service_group_by
                      }

                      secondaryAggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_PERCENTILE_95"
                      }
                    }

                    unitOverride = "10^2.%"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "CPU utilization"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 12
          width  = 6
          height = 4

          widget = {
            title = "Memory utilization p95"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.cloud_run_dashboard_resource_filter} AND metric.type=\"run.googleapis.com/container/memory/utilizations\""

                      aggregation = {
                        alignmentPeriod    = "300s"
                        perSeriesAligner   = "ALIGN_SUM"
                        crossSeriesReducer = "REDUCE_SUM"
                        groupByFields      = local.dashboard_service_group_by
                      }

                      secondaryAggregation = {
                        alignmentPeriod  = "300s"
                        perSeriesAligner = "ALIGN_PERCENTILE_95"
                      }
                    }

                    unitOverride = "10^2.%"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "memory utilization"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          yPos   = 16
          width  = 6
          height = 4

          widget = {
            title = "Production external uptime success"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.production_uptime_resource_filter} AND metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\""

                      aggregation = {
                        alignmentPeriod    = "900s"
                        perSeriesAligner   = "ALIGN_NEXT_OLDER"
                        crossSeriesReducer = "REDUCE_FRACTION_TRUE"
                      }
                    }

                    unitOverride = "10^2.%"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "successful checkers"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        },
        {
          xPos   = 6
          yPos   = 16
          width  = 6
          height = 4

          widget = {
            title = "Production external uptime latency p95"

            xyChart = {
              dataSets = [
                {
                  timeSeriesQuery = {
                    timeSeriesFilter = {
                      filter = "${local.production_uptime_resource_filter} AND metric.type=\"monitoring.googleapis.com/uptime_check/request_latency\""

                      aggregation = {
                        alignmentPeriod    = "900s"
                        perSeriesAligner   = "ALIGN_MEAN"
                        crossSeriesReducer = "REDUCE_PERCENTILE_95"
                      }
                    }

                    unitOverride = "ms"
                  }

                  plotType           = "LINE"
                  minAlignmentPeriod = "60s"
                  targetAxis         = "Y1"
                }
              ]

              yAxis = {
                label = "milliseconds"
                scale = "LINEAR"
              }

              chartOptions = {
                mode = "COLOR"
              }
            }
          }
        }
      ]
    }
  })

  depends_on = [google_project_service.monitoring]
}
