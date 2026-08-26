# Phase 11 Observability Verification

Infrastructure verification date: 2026-08-25.

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

## Runtime evidence pending delivery

The current production image predates the new `external` health group. Until
the Phase 11 application image is delivered, the newly created uptime check can
report the path as unavailable. This is expected transitional state, not proof
of a Phase 11 health failure.

After the branch is merged and the image is deployed to development, record:

1. a healthy public `/actuator/health/external` response and the production
   uptime check reporting success after production delivery;
2. a structured completion log whose `severity`, `request_id`, `http_method`,
   `http_path`, `http_status`, and `duration_ms` fields are searchable;
3. a manual review confirming that recent entries contain no database URL,
   credentials, authorization/cookie values, query strings, or bodies;
4. a development-only controlled HTTP 500 correlated by `X-Request-ID` with its
   ERROR log and both relevant metrics;
5. the error-rate incident grouped under `cloud-native-api-dev` and the received
   email notification; and
6. removal of the temporary revision tag followed by a reviewed Terraform apply
   with `enable_development_test_error=false`, proving the endpoint is absent
   again.

No deliberate failing request is sent to production. Resource names, statuses,
metric values, incident identifiers, and workflow links may be recorded, but
the email address, Terraform state, saved plans, secret values, tokens, and
database connection strings must not be included.

## Expected usage

The dashboard reads existing Monitoring series and sends no application
traffic. The application ERROR counter has no custom labels and is expected to
remain low volume. One 15-minute production uptime check executed by four
regional checkers is approximately 11,520 checks in a 30-day month, within the
current published free allowance for this project's expected use. The check can
still cause Cloud Run cold starts and Supabase connections, so the official
[Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
must be reviewed again if the environment is retained or its traffic grows.
