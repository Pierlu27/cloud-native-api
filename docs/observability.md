# Observability

This guide explains the Phase 11 observability model, how its signals flow
through Google Cloud, and how to use them without confusing logs, metrics,
health checks, and alerts.

## Logs, metrics, and traces

- A **log** is a detailed record of one event. It answers questions such as
  "what failed?", "which request was involved?", and "what did the application
  report?" Logs retain searchable context but are not ideal for calculating a
  service-wide trend on their own.
- A **metric** is a numeric time series. It answers questions such as "how many
  requests arrived?", "what percentage failed?", or "what was p95 latency?"
  Metrics deliberately retain fewer dimensions than logs so their cardinality
  and cost remain predictable.
- A **trace** follows one operation across multiple processes and dependencies.
  It is most useful when a request crosses several services. Distributed
  tracing is deferred because this project currently has one application
  service; request IDs, structured logs, and platform metrics provide the
  intended learning value without another telemetry pipeline.

Phase 11 implements logs and metrics. A dashboard visualizes the metrics, while
alert policies continuously evaluate them and can open incidents.

## Structured request logging

```text
HTTP request
   -> RequestLoggingFilter validates or generates X-Request-ID
   -> the filter stores request_id, http_method, and http_path in MDC
   -> controller, service, repository, and exception-handler logs inherit MDC
   -> the filter logs http_status and duration_ms when processing completes
   -> the filter clears MDC before the servlet worker thread is reused
   -> Spring writes one Logstash JSON object to stdout
   -> Cloud Run forwards stdout to Cloud Logging
   -> Cloud Logging recognizes severity and indexes the remaining JSON fields
```

MDC (Mapped Diagnostic Context) is request-local metadata associated with the
current execution thread. It avoids passing a request ID through every method
parameter. Servlet worker threads are reused, so the filter owns the complete
MDC lifecycle and clears its three values in a `finally` block even when the
request throws an exception.

The caller's `X-Request-ID` is retained only when it contains 1-128 letters,
digits, dots, underscores, or hyphens. Otherwise the application generates a
UUID. The selected value is returned in the response header so a caller can
search for the same request in Cloud Logging.

A request-completion entry contains these application fields in addition to
Spring's normal timestamp, logger, thread, message, and exception fields:

| Field | Meaning |
|---|---|
| `severity` | Cloud Logging-recognized `INFO`, `WARN`, or `ERROR` level |
| `request_id` | validated caller ID or generated UUID |
| `http_method` | request method such as `GET` or `POST` |
| `http_path` | path without the query string |
| `event` | stable event name, currently `http_request_completed` |
| `http_status` | final HTTP response status |
| `duration_ms` | total time spent in the application filter chain |

Healthy Cloud Run liveness and readiness probes are omitted from application
completion logs to avoid repetitive noise. Their failures are still logged.
The external uptime request is not suppressed because it represents an
end-to-end availability signal.

Logs must not include authorization or cookie headers, query strings, complete
request bodies, database credentials, or connection strings. Hibernate's
connection-pooling logger is kept at `WARN` so its startup summary cannot place
the complete JDBC URL in normal INFO logs.

Useful Cloud Logging filters include:

```text
resource.type="cloud_run_revision"
resource.labels.service_name="cloud-native-api-dev"
jsonPayload.event="http_request_completed"
jsonPayload.http_status=500
```

```text
resource.type="cloud_run_revision"
resource.labels.service_name="cloud-native-api-dev"
jsonPayload.request_id="<request-id>"
```

## Health endpoints

Cloud Run continues to call the lifecycle endpoints used since Phase 2:

- startup and readiness: `/actuator/health/readiness`;
- liveness: `/actuator/health/liveness`.

Those probes answer whether Cloud Run should start, route to, or restart a
container. Database availability is intentionally not added to liveness: an
external Supabase outage must not cause every otherwise healthy JVM to restart.

`/actuator/health/external` is a separate Spring Actuator health group containing
`readinessState` and `db`. It returns success only when the application is ready
and Hikari can obtain a database connection. This endpoint is intended for
external service monitoring, not container lifecycle management.

Google Cloud Monitoring calls the production endpoint over public HTTPS every
15 minutes, requires a 2xx response, validates TLS, and verifies that JSON field
`$.status` equals `UP`. Checkers are selected from Europe and the USA. Because
this is a real public request, it may cause a Cloud Run cold start and a
Supabase connection while the application otherwise has no traffic.

## Metrics and dashboard

The shared `Cloud Native API - Observability` dashboard groups platform series
by Cloud Run `service_name`, so development and production remain separate
lines rather than being combined.

| Signal | Source | Interpretation |
|---|---|---|
| Request count | native `run.googleapis.com/request_count` | requests received in each five-minute window |
| 5xx error rate | native 5xx request count / native total request count | fraction of requests that failed, per environment |
| Latency p50/p95 | native request-latency distribution | median and slow-tail request latency |
| Phase 8 HTTP 5xx count | preserved `cloud-native-api-http-5xx` log metric | absolute number of HTTP server-error request logs |
| Application ERROR entries | `cloud-native-api-application-errors` log metric | number of structured stdout entries with `severity >= ERROR` |
| CPU/memory p95 | native Cloud Run distributions | high-percentile container resource utilization |
| Production uptime | uptime-check metrics | fraction of checkers seeing `UP` and their p95 request latency |

The application ERROR counter is not a failed-request counter. One request can
produce multiple ERROR entries, and a startup or background failure can produce
an ERROR without an HTTP request. Request IDs, paths, messages, and exceptions
remain in logs instead of becoming metric labels; this prevents an unbounded
number of metric time series.

For latency, CPU, and memory, the dashboard first combines the underlying
distributions while preserving their sample weights and only then calculates
the percentile. Calculating a percentile independently for many tiny series and
then combining those percentiles would give a one-request series the same
importance as a high-traffic series.

## Alert policies

Two different alerts coexist:

1. The Phase 8 policy opens a console incident after at least one HTTP 5xx is
   observed by the preserved log-based counter. It has no notification channel.
2. The Phase 11 policy uses the native Cloud Run request metric. It calculates
   `5xx requests / all requests` independently for each `service_name`, opens an
   incident when the result is above 20% for 60 seconds, and sends it to the
   Terraform-managed email channel. Its numerator and denominator both use a
   five-minute alignment window. Missing traffic is inactive, so scale-to-zero
   does not look like a failure.

The 60-second duration does not mean that one HTTP response remains "500" for a
minute. Monitoring repeatedly evaluates a time-series condition; the calculated
error rate must remain in violation for 60 seconds before the incident opens.
An incident can close sooner when new data shows the condition is healthy again;
the configured 30-minute auto-close covers the separate case where matching
data stops arriving.

The notification address is required through the ignored local
`terraform.tfvars`. Terraform marks it sensitive to reduce accidental CLI
display, but the value still exists in local Terraform state and in Cloud
Monitoring. Neither the address nor state output belongs in committed evidence.

## Controlled development error test

`POST /internal/observability/test-error` throws a controlled unexpected
exception through the normal global exception handler. The controller does not
exist unless `observability.test-error.enabled=true`.

Terraform exposes `enable_development_test_error`, defaults it to `false`, and
injects `OBSERVABILITY_TEST_ERROR_ENABLED=true` only into the development Cloud
Run template. Production can never receive the variable through this resource.
Changing the variable creates a new Cloud Run revision because environment
variables are part of a revision's immutable template.

There is an additional operational consequence of the Phase 9 ownership split.
The workflow gives every application revision an explicit name, while Terraform
normally ignores that workflow-owned field. After refresh, however, the Google
provider still knows the current explicit name. If a later Terraform operation
changes the structural template, the provider can attempt to create the changed
template under that same name; Cloud Run rejects this with HTTP 409 because
revisions are immutable.

For a manual structural exercise such as this controlled test, temporarily use
a new unique development revision name and keep production at its current name,
then remove `template[0].revision` from `ignore_changes` only for the reviewed
operation. The plan must change development alone. Use a second unique name for
the disabled cleanup revision. These runtime-specific names remain uncommitted;
after cleanup, remove the override, restore the lifecycle ignore rule, refresh
the asynchronous latest-ready output if necessary, and require a final no-op
plan. This does not transfer long-term revision ownership to Terraform: it is a
bounded workaround for a manually applied structural change.

The end-to-end test is performed only after the Phase 11 image has reached
development:

1. confirm the endpoint is absent from the current disabled development
   revision;
2. prepare the unique uncommitted revision-name override, enable the Terraform
   variable, review that the plan changes only development, and apply it;
3. route a temporary Cloud Run tag to the new enabled revision without moving
   normal development traffic;
4. call the tagged endpoint and retain its HTTP 500 response and
   `X-Request-ID`;
5. correlate that ID with the structured ERROR log, application-error metric,
   native error rate, Monitoring incident, and email notification;
6. remove the temporary tag;
7. select another unique development revision name, set the variable back to
   `false`, review and apply Terraform again, and confirm the endpoint is absent
   from the clean revision;
8. remove the validation tag and temporary name override, restore revision-name
   ignoring, refresh state-only computed outputs when required, and confirm a
   normal `terraform plan` reports `No changes`.

A traffic rollback can immediately isolate the test revision, but it does not
replace the final disabled Terraform apply. The declared service template must
also return to its safe default.

The development exercise completed on 2026-08-26. One controlled HTTP 500
produced one native 5xx request, one preserved Phase 8 5xx event, and two
application `ERROR` entries sharing the returned request ID. Both alert policies
opened incidents, the greater-than-20% error-rate notification email arrived,
and the incidents closed after the signal returned healthy. The clean revision
then returned HTTP 200/`UP` for external health and HTTP 404 for the disabled
fault endpoint. All temporary tags were removed and Terraform converged to a
no-op plan.

## Usage and cost boundary

The project primarily uses native Cloud Run metrics, which do not require a
second ingestion pipeline. The custom application-error metric has no
high-cardinality labels and is expected to receive very little data. The one
production uptime check runs every 15 minutes; four regional checkers produce
approximately 11,520 executions in a 30-day month. This is below the currently
published free allowance for the project's expected usage, but it still wakes
Cloud Run and queries Supabase.

Pricing and allowances can change. Recheck the official
[Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
before leaving the didactic environment active long term, and remove or disable
the uptime check when continuous monitoring is no longer wanted. The dashboard
itself does not poll the application or prevent scale-to-zero.
