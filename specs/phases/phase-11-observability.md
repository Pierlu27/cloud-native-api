# Spec: Phase 11 - Observability

## 1. Goal

Understand what happens to the application once it is running in production, by implementing structured logging, a health endpoint, and basic monitoring and alerting through Cloud Logging and Cloud Monitoring.

## 2. Scope

In scope:

- structured (JSON) application logging produced through Spring Boot's native
  structured-logging support and written to stdout, so Cloud Run automatically
  ingests it into Cloud Logging without a provider-specific logging appender
- request correlation through an HTTP filter and MDC, with a validated or
  generated request identifier returned to the caller
- a dedicated `/actuator/health/external` health group, extending the Actuator
  health support introduced in Phase 2 and exposed for external monitoring
  without changing the Cloud Run startup, readiness, or liveness probe paths
- a Terraform-managed public uptime check for the production service, executed
  every 15 minutes against `/actuator/health/external`, to verify the complete
  externally visible path including database connectivity
- a temporary development-only fault-injection endpoint used to verify the
  complete error log, metric, alert, and notification path without sending a
  deliberate HTTP 5xx request to production
- basic Cloud Monitoring metrics: request count, latency, error rate, CPU, memory, and application error count
- additive observability changes that preserve the Phase 8
  `cloud_run_http_5xx` log-based metric and its existing count-based alert
  policy without changing their meaning or behavior
- at least one basic alerting policy (e.g. high error rate or high latency) with a notification channel configured
- documentation of the difference between logs, metrics, and traces, and why this project focuses on logs and metrics for now

Out of scope:

- distributed tracing (explicitly deferred to a future, distributed-systems-focused project, per the project roadmap)
- log-based custom metrics beyond the basic set listed above
- advanced alerting (e.g. multi-condition policies, anomaly detection, SLO-based alerting)
- observability for the Jenkins pipeline itself (Phase 13-17, handled separately if applicable)

## 3. Functional requirements

1. The application must use Spring Boot's native structured-logging support to
   emit one JSON object per line to stdout. The resulting schema must expose a
   top-level `severity` field recognized natively by Cloud Logging (e.g.
   `INFO`, `WARNING`, `ERROR`) while keeping ordinary application fields in
   `jsonPayload`; no Google-specific logging appender is required.
2. Every request-scoped log entry must include a request identifier, HTTP
   method, and request path through MDC. The request-completion entry must also
   contain the final response status and total duration. Logs emitted outside
   an HTTP request, such as startup and shutdown events, are not required to
   contain HTTP context. No entry may include credentials, authorization or
   cookie headers, query strings, or full request bodies containing personal
   data.
3. `/actuator/health/external` must be reachable through the public service URL
   and explicitly aggregate Spring's `readinessState` and `db` health
   indicators. It must return HTTP 200 with `UP` only when the application is
   ready and the datasource can obtain a database connection, and return a
   non-success status when either member is unhealthy. The existing Cloud Run
   startup/readiness probes must remain on `/actuator/health/readiness`, and the
   liveness probe must remain on `/actuator/health/liveness`, so an external
   database outage does not cause container restart loops.
4. Cloud Monitoring must execute a public uptime check against the production
   `/actuator/health/external` endpoint every 15 minutes. Development must not
   receive a periodic uptime check, so the learning objective is met without
   generating recurring traffic in both environments.
5. Cloud Monitoring must have visibility into, at minimum: request count,
   request latency (e.g. p50/p95), HTTP 5xx error rate, CPU utilization, memory
   utilization, and application error count. The HTTP error rate must be the
   ratio of native Cloud Run 5xx request count to total request count over the
   same alignment window; it must not be represented by the absolute number of
   errors. The application error count must instead come from a low-cardinality
   log-based counter named `Application ERROR log entries`, matching every new
   structured application entry with `severity >= ERROR`. This counter measures
   log events rather than unique failed requests: one request may legitimately
   contribute more than one entry, and non-request failures may also contribute.
   Request identifiers, paths, messages, and exception values must not be
   extracted as metric labels, so the metric retains low cardinality.
   The ratio must filter the existing native
   `run.googleapis.com/request_count` metric at evaluation time; it must not
   create another log-based HTTP 5xx metric. The Phase 8
   `cloud_run_http_5xx` metric and its count-based alert policy must remain
   managed and unchanged as separate, previously delivered signals.
   One Terraform-managed `Cloud Native API - Observability` dashboard must
   present development and production as distinct `service_name` series in a
   shared view. It must include request count, request-latency p50 and p95,
   native HTTP 5xx error rate, the preserved Phase 8 absolute HTTP 5xx count,
   `Application ERROR log entries`, CPU utilization, memory utilization, and
   production external uptime status and check latency. A separate dashboard
   per environment is not required for the two-service scope of this project.
6. One shared Cloud Monitoring alerting policy must evaluate development and
   production independently by grouping the native Cloud Run request series by
   `service_name`. It must open an incident when the HTTP 5xx error rate is
   greater than 20% in a five-minute alignment window. Missing data must be
   treated as inactive, because an environment with zero requests due to Cloud
   Run scale-to-zero is not unhealthy.
7. The shared alerting policy must have an email notification channel attached
   so an incident actually reaches a person, not just the Cloud Monitoring
   dashboard. Its end-to-end trigger must be tested only against development;
   no deliberate HTTP 5xx request may be sent to production for this test.
   Terraform must create the channel with `force_delete=false` and read the
   destination from a required sensitive `alert_notification_email` variable.
   The real address must exist only in the ignored local `terraform.tfvars`,
   never in committed configuration or example values. Sensitive marking hides
   normal CLI output but does not remove the address from Terraform state or
   from Cloud Monitoring. The channel must be attached only to the new
   error-rate policy; the Phase 8 count-based alert remains unchanged. After
   creation, its computed verification status must be checked and any required
   provider verification completed before the end-to-end notification test.
8. A `POST /internal/observability/test-error` endpoint must deliberately throw
   an unexpected exception through the normal application exception-handling
   path, producing a structured `ERROR` entry and HTTP 500 response. Spring
   must register this controller only when
   `observability.test-error.enabled=true`. Terraform must expose a boolean
   input with a `false` default and inject its environment variable only into
   the `development` Cloud Run service when explicitly enabled; the production
   instance must never receive it. After the test, a Terraform apply with the
   default disabled value must remove the variable and create a clean
   development revision. Traffic rollback to the previous disabled revision is
   an optional immediate containment action, not a substitute for reconciling
   the Terraform-managed service template back to disabled.
9. Log entries must be searchable in Cloud Logging by their structured fields (e.g. filtering by `severity=ERROR` or by a specific request identifier), not only by full-text search.

## 4. Non-functional requirements

- CI gate: no functional changes to triggers, jobs, permissions, validation,
  publishing, or deployment are required in this phase. The only workflow edit
  is the previously deferred display-name correction from `CI` to `CI/CD`,
  included with the application and infrastructure work rather than run as a
  standalone documentation-only change.
- Security: logs must never include secret values, full credentials, or unnecessary personal data; log content must be reviewed as part of this phase to confirm no sensitive data leaks into Cloud Logging.
- Observability: this phase is observability itself, so its own non-functional requirement is completeness — logs, basic metrics, and at least one alert must all be verified working end to end before the phase is considered done.

## 5. Acceptance criteria

- [x] application logs appear in Cloud Logging as structured JSON, with `severity` correctly recognized (visible as log level in the Cloud Logging Console, not buried in raw text)
- [x] a log entry can be filtered in Cloud Logging by a structured field (e.g. `jsonPayload.http_status=500`) and this returns the expected results
- [x] `/actuator/health/external` returns a healthy status when the application
  and its database connection are working, and returns an unhealthy status in
  a controlled simulation when the database is unreachable, without changing
  the Cloud Run startup/readiness/liveness probe behavior
- [x] a production-only uptime check calls `/actuator/health/external` every 15
  minutes and reports the endpoint as available in Cloud Monitoring
- [x] one Terraform-managed dashboard compares `dev` and `prod` by
  `service_name` and shows request count, latency p50/p95, native 5xx error
  rate, preserved Phase 8 absolute 5xx count, application `ERROR` log entries,
  CPU utilization, memory utilization, and production uptime status/latency
- [x] the Phase 8 `cloud_run_http_5xx` metric and its count-based alert remain
  present and retain their original behavior; the new error-rate query uses
  the native `run.googleapis.com/request_count` metric instead
- [x] a deliberately triggered error (e.g. an intentionally broken request)
  shows up as a structured application error, increments the log-based
  `Application ERROR log entries` counter by one or more matching log events,
  and changes the native Cloud Run HTTP 5xx error rate
- [x] the shared 5xx error-rate policy evaluates `dev` and `prod` as separate
  `service_name` groups, treats missing traffic as inactive, and fires above
  20% in a five-minute window
- [x] a controlled development-only trigger opens an incident and sends a
  notification to the configured email channel without deliberately producing
  a 5xx response in production
- [x] the email address is absent from tracked files, the Terraform-managed
  channel is usable rather than `UNVERIFIED`, and it is referenced only by the
  new error-rate policy
- [x] the fault-injection endpoint is absent by default and in production,
  becomes reachable only in a specifically enabled development revision,
  exercises the normal global exception handler, and is disabled again through
  a reviewed Terraform plan and apply after the alert test
- [x] no sensitive data (credentials, secrets, full connection strings) is found in a manual review of recent log entries

## 6. Deliverables

- code: Spring Boot native structured-logging configuration adapted to expose
  GCP-recognized severity levels, an HTTP request-correlation filter that owns
  the MDC lifecycle, and an externally reachable health check endpoint
- infrastructure: a Terraform-managed production uptime check for the external
  health endpoint, in addition to the dashboard, metrics, alerting policy, and
  notification channel
- compatibility: the Terraform-managed Phase 8 HTTP 5xx metric and alert policy
  remain intact; Phase 11 observability resources are added alongside them
- workflow: display-only rename of `.github/workflows/ci.yml` from `CI` to
  `CI/CD`; no functional pipeline behavior changes
- documentation: updated `docs/architecture.md` (or a new `docs/observability.md`) explaining the logs/metrics/traces distinction, what is implemented in this phase, what is deferred, and how to read the Cloud Monitoring dashboard and alerts

## 7. Evidence

- sample structured log entries (raw JSON) exported from Cloud Logging, showing recognized `severity` and contextual fields
- `gcloud logging read` output filtering log entries by a structured field (e.g. `jsonPayload.http_status=500`)
- `gcloud monitoring` or Cloud Monitoring API output confirming request count, latency, error rate, CPU, and memory metrics exist for the Cloud Run service
- `/actuator/health/external` response body for a healthy deployed environment
  and for a locally controlled unavailable-database simulation, plus evidence
  that Cloud Run still targets the original readiness and liveness paths
- Cloud Monitoring or Terraform output confirming that the production uptime
  check targets `/actuator/health/external` with a 15-minute period
- notification log or message content confirming the alerting policy fired during a test, including the channel it was delivered to
- output of a deliberately triggered error request, correlated with its corresponding log entry and metric increment

## 8. Risks and mitigations

- risk: logging too much detail (e.g. full request/response bodies) could leak sensitive data into Cloud Logging, which is harder to purge retroactively than to prevent from happening in the first place.
  mitigation: define explicit logging guidelines (what fields are safe to log) before writing logging code, and review a sample of real log entries as part of this phase's acceptance criteria.
- risk: an alerting policy with too sensitive a threshold could generate
  frequent false alarms, leading to alert fatigue similar to the one already
  discussed for security scanning in Phase 4.
  mitigation: evaluate a 20% error-rate threshold over five-minute aligned
  windows, keep missing data inactive, and retain `service_name` grouping so
  development failures don't alter production's calculated ratio. Revisit the
  threshold if the services later receive meaningful real traffic.
- risk: user-defined log-based metrics, stored logs, uptime executions, and
  automated Monitoring API reads can become chargeable after their respective
  free monthly allowances are exhausted or pricing changes.
  mitigation: use native non-chargeable Cloud Run metrics wherever possible,
  keep the application error metric low-cardinality, monitor only production
  with the uptime check, and review the official Observability pricing and
  actual billing usage before applying this phase and when keeping it active
  long term.
- risk: leaving a public fault-injection endpoint enabled would let callers
  generate artificial failures, log volume, and alerts.
  mitigation: conditionally register it, default the Terraform toggle to false,
  make the toggle structurally development-only, use it for one controlled
  request, and require a final disabled Terraform apply. Use traffic rollback
  for immediate containment if needed, then still reconcile the template.
- risk: after a workflow-named Cloud Run revision has been refreshed into
  Terraform state, a structural template update can make the provider reuse
  that immutable revision name and Cloud Run rejects the update with HTTP 409.
  mitigation: for a reviewed manual structural apply, temporarily provide a
  new unique development revision name while preserving production's current
  name, stop ignoring the revision field only for that operation, and inspect
  that the plan changes development alone. Use another unique name for the
  cleanup revision, then remove the uncommitted override, restore the normal
  lifecycle boundary, refresh the state, and require a final no-op plan.
- risk: marking the notification email variable as sensitive can be mistaken
  for encryption or omission from state.
  mitigation: keep the real value only in ignored local inputs, document that
  state and the Google resource still contain it, restrict state access, and
  never place the address in committed examples or evidence.
- risk: relying only on unstructured text logs would make it very hard to correlate a specific failed request with its cause during an incident.
  mitigation: enforce structured JSON logging with a request identifier from the start, rather than retrofitting it later once debugging an incident becomes urgent.
- risk: treating the application `ERROR` log-entry counter as a failed-request
  counter would be misleading because one request can emit multiple error logs
  and application errors can occur outside HTTP request processing.
  mitigation: name and document the metric as `Application ERROR log entries`,
  use the native Cloud Run ratio for failed-request alerting, and keep
  high-cardinality context such as `request_id` in logs rather than metric
  labels.
- risk: servlet worker threads are reused, so request context left in MDC could
  be attached to a later unrelated request.
  mitigation: make the HTTP filter the owner of the request MDC lifecycle and
  clear it unconditionally in a `finally` block, including when request
  processing throws an exception.
- risk: since distributed tracing is explicitly out of scope for this project, diagnosing latency issues that span multiple calls (e.g. app to Supabase) will rely entirely on logs and metrics, which can make root-causing slow requests harder than with full tracing.
  mitigation: ensure latency is logged per request (not just aggregated in metrics) so that at least request-level timing detail is available without full distributed tracing.
- risk: adding database connectivity to the Cloud Run liveness or readiness
  probes could remove every instance from traffic or restart healthy containers
  during an external Supabase outage.
  mitigation: keep the existing platform probes unchanged and isolate the
  dependency-aware check in the dedicated `external` health group; simulate
  its negative state locally rather than disrupting the production database.
- risk: unlike Cloud Run's internal probes, a public uptime check is a real
  request. With zero minimum instances it can cause a cold start and a database
  connection, and therefore consumes Cloud Run, Monitoring, and Supabase
  quotas even when no user is calling the application.
  mitigation: monitor production only and use a 15-minute period. This is about
  2,880 checks per month before accounting for execution regions and remains
  well inside the current free monthly allowances for this project's expected
  usage; remove or disable the check when the didactic environment is no longer
  intended to be monitored.

## 9. Definition of done (phase)

- [x] implementation complete (structured logging, externally reachable health check, Cloud Monitoring dashboard, at least one alerting policy with a notification channel)
- [x] tests pass (a deliberately triggered error is visible in both logs and metrics; the alert fires correctly during a test)
- [x] expected observability usage has been checked against the current Google
  Cloud free allowances, with any recurring or future-cost resources documented
- [x] documentation updated (logs/metrics/traces explanation and dashboard/alert usage documented)
- [x] decisions recorded (e.g. logging library choice, alert threshold rationale, decision to defer tracing) in `docs/decisions.md` or equivalent

## 10. Current implementation status

Development runtime verification completed on 2026-08-26. The controlled
request produced HTTP 500 with a searchable request ID, one native HTTP 5xx,
one preserved Phase 8 HTTP 5xx, and two application `ERROR` log entries. Both
the absolute-count and greater-than-20%-rate incidents opened and closed, and
the configured email notification was received. A second reviewed Terraform
apply created a clean revision without the enabling variable; its external
health returned HTTP 200/`UP`, the fault endpoint returned the expected HTTP
404, all temporary tags were removed, and the final Terraform plan reported
`No changes`. A review of 133 recent application entries found no configured
sensitive-data indicators.

Production runtime verification also completed on 2026-08-26. Pull request
`#34` merged Phase 11 into `main` at commit
`47c136fb45fd5625f5a1f95e7f46710855d1eeec`. Because no automatic push run
appeared for that merge, the complete production workflow was manually
dispatched for the same commit. Run `32977172126` passed every gate, deployed
and smoke-tested a no-traffic candidate, and promoted revision
`cloud-native-api-prod-sha-47c136fb-run-32977172126` to 100 percent traffic
after environment approval. Production external health returned HTTP 200/`UP`,
the disabled fault endpoint returned HTTP 404 without producing a production
5xx, and the production-only Oregon uptime checker reported
`check_passed=true` at `2026-08-26T14:07:00Z`. Phase 11 is complete.
