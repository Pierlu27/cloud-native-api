# Phase 11 Observability Verification

Infrastructure verification date: 2026-08-25.
Development runtime verification date: 2026-08-26.

This document separates completed implementation and infrastructure evidence
from runtime checks that require the Phase 11 application image to be delivered
to development. Commands and sanitized text results are sufficient evidence;
Console screenshots are not mandatory.

## Local application verification

The focused tests verify that the request filter:

- retains a safe caller-provided request ID and otherwise generates a UUID;
- returns the selected ID in `X-Request-ID`;
- emits the expected request context, status, duration, and severity;
- treats a propagated exception as HTTP 500 for its completion log;
- suppresses successful internal probe noise; and
- clears MDC after every request.

The controller tests verify that the fault endpoint is absent by default,
appears only when `observability.test-error.enabled=true`, and exercises the
real global exception handler to return HTTP 500 with a request ID.

The application integration test verifies `/actuator/health/external` as `UP`
with its Testcontainers PostgreSQL connection and as HTTP 503/`DOWN` after that
database is stopped. Cloud Run's configured startup/readiness and liveness paths
remain `/actuator/health/readiness` and `/actuator/health/liveness`.

Focused tests and Checkstyle passed during implementation. On 2026-08-26 the
complete Gradle test suite also completed with `BUILD SUCCESSFUL`, including
the Testcontainers-backed application and controller integration tests. An
initial attempt started before Docker Desktop's Linux engine was ready and the
two Testcontainers classes could not initialize; rerunning the unchanged suite
after `docker version` confirmed the engine was available produced the
successful result.

## Applied infrastructure

Terraform created:

- `cloud-native-api-application-errors`, a low-cardinality counter over
  structured stdout entries with `severity >= ERROR`;
- one production uptime check for `/actuator/health/external`, with a 900-second
  period, 30-second timeout, HTTPS validation, 2xx requirement, and
  `$.status == "UP"` content match;
- the shared `Cloud Native API - Observability` dashboard;
- one email notification channel whose real address remains only in ignored
  local input and Terraform state; and
- the native Cloud Run HTTP 5xx error-rate policy, grouped independently by
  `service_name`, with a 20% threshold, five-minute alignment, 60-second
  duration, and inactive missing data.

The first policy apply exposed a Google Monitoring API constraint:
`evaluation_missing_data` cannot be combined with a zero duration. The duration
was corrected to the API's non-zero 60-second minimum before the policy was
created.

The Monitoring API also normalizes dashboard JSON by omitting zero coordinates
and adding the default `Y1` target axis. The Terraform configuration was aligned
with that representation rather than hiding the entire dashboard through
`ignore_changes`. The final remote comparison reported:

```text
No changes. Your infrastructure matches the configuration.
```

No Phase 8 resource was removed or redefined. The original absolute 5xx metric
and its console-only count alert remain managed alongside the new resources.

Terraform and a direct `notificationChannels.get` API request both returned an
empty `verificationStatus`, corresponding to
`VERIFICATION_STATUS_UNSPECIFIED`, not `UNVERIFIED`. The
[Monitoring API reference](https://docs.cloud.google.com/monitoring/api/ref_v3/rest/v3/projects.notificationChannels#VerificationStatus)
defines only `UNVERIFIED` as requiring verification before a channel can
function; any other result is assumed usable. No provider verification step is
therefore required before the controlled notification test.

## Development runtime evidence

The Phase 11 image reached development through the normal delivery workflow.
The tagged enabled revision
`cloud-native-api-dev-observability-test-20260826` returned HTTP 200/`UP` from
`/actuator/health/external` before the controlled error was sent. Normal
development traffic remained at 100 percent on the preceding disabled stable
revision throughout the exercise.

One `POST /internal/observability/test-error` returned HTTP 500 with request ID
`750c47e8-48c1-40a4-be19-14d064a6ff94`. Filtering Cloud Logging by the
structured `jsonPayload.request_id` field returned two correlated `ERROR`
entries:

- the global exception-handler entry identified the controlled
  `IllegalStateException`, method, and path; and
- the request-completion entry recorded `http_status=500` and
  `duration_ms=63`.

The Monitoring API reported, for the enabled revision in the corresponding
minute, one native Cloud Run HTTP 5xx request, one preserved Phase 8 log-based
HTTP 5xx, and two `Application ERROR log entries`. The two application entries
are expected because this counter measures log events rather than unique
requests.

The Phase 8 `Cloud Run HTTP 5xx detected` incident opened at 10:11:28 UTC and
closed at 10:15:55 UTC. The Phase 11 `Cloud Run HTTP 5xx error rate above 20%`
incident opened at 10:12:34 UTC and closed at 10:16:45 UTC, grouped under
`cloud-native-api-dev`; the configured email notification was received. No
deliberate failing request was sent to production.

After the test, the public tag was removed and a second reviewed Terraform plan
reported `0` additions, `1` in-place change, and `0` destructions. Applying it
created `cloud-native-api-dev-observability-clean-20260826` without
`OBSERVABILITY_TEST_ERROR_ENABLED`. Through a temporary validation tag the
clean revision returned HTTP 200/`UP` for external health and HTTP 404
`Resource not found` for the fault endpoint. The validation tag was then
removed, a refresh-only apply recorded Cloud Run's asynchronous latest-ready
output, and the final normal plan reported:

```text
No changes. Your infrastructure matches the configuration.
```

A review of 133 recent development stdout/stderr entries found zero matches for
JDBC/PostgreSQL URLs, datasource variable names, serialized username/password
pairs, authorization or cookie headers, Bearer tokens, query-string fields, or
request-body fields. The observed structured fields were limited to logging
metadata plus request ID, method, path, event, status, duration, message, and
stack trace.

The first enable apply safely failed before changing Cloud Run because the
provider attempted to reuse the latest workflow-owned explicit revision name.
Cloud Run revisions are immutable, so the successful enable and cleanup plans
used separate, unique, uncommitted Terraform revision-name overrides. The
normal lifecycle ignore rule was restored after cleanup. This operational edge
case and its safe procedure are now documented in the deployment runbook.

Resource names, statuses, metric values, incident identifiers, and workflow
links may be recorded, but the email address, Terraform state, saved plans,
secret values, tokens, and database connection strings must not be included.

## Production runtime evidence pending

The current production image predates the new `external` health group. Until
the Phase 11 application image is promoted to `main`, the uptime check can
report that path as unavailable. After production delivery, verify a healthy
public `/actuator/health/external` response, the fault endpoint's safe disabled
state, and a successful 15-minute uptime-check result. This transitional state
is not proof of a Phase 11 health failure.

## Expected usage

The dashboard reads existing Monitoring series and sends no application
traffic. The application ERROR counter has no custom labels and is expected to
remain low volume. One 15-minute production uptime check executed by four
regional checkers is approximately 11,520 checks in a 30-day month, within the
current published free allowance for this project's expected use. The check can
still cause Cloud Run cold starts and Supabase connections, so the official
[Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
must be reviewed again if the environment is retained or its traffic grows.
