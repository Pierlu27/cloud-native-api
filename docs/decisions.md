# Architecture Decision Log

## ADR-001 Cloud Run

**Decision**: use Cloud Run as the initial compute layer.  
**Reason**: simpler operations, autoscaling, learning focus on CI/CD.

## ADR-002 Managed PostgreSQL provider

**Decision**: use Supabase Free PostgreSQL with the Supavisor Session Pooler.
**Reason**: keep the managed database at zero cost while separating the data
layer from Cloud Run. Cloud SQL is explicitly deferred because stopped
instances can still incur storage and IP charges. TLS is required and
credentials are injected into Cloud Run through Secret Manager references
managed in Phase 8; their payloads remain outside Terraform configuration and
state.

## ADR-003 Terraform

**Decision**: manage the Phase 8 GCP infrastructure with a flat Terraform root
module and local state. Organize the root module into thematic `.tf` files but
do not introduce child modules, workspaces, or a remote backend yet. Adopt the
existing GCP resources with `terraform import` and use a separate state when
targeting another project.

**Reason**: Terraform provides reproducible, versioned, reviewable declarations
without adding multi-environment orchestration before it is needed. Terraform
loads all `.tf` files in the root directory as one module, so splitting the
configuration improves readability without changing resource addresses. Local
state is sufficient for the current single-developer learning phase; the import
runbook makes its resource mappings recoverable if the local state is lost.

## ADR-004 GitHub Actions

**Decision**: run CI/CD on GitHub Actions.  
**Reason**: native repository integration and DevOps learning path.

## ADR-005 Local Docker Compose stack

**Decision**: package the API with a multi-stage Docker build using an Eclipse Temurin
Alpine JRE runtime, run it as a non-root user, and use Docker Compose with a named
PostgreSQL volume for local development.

**Reason**: the runtime image contains only the application, JRE and health-check tool;
the non-root user reduces container privileges; the named volume preserves local data
across compose restarts while keeping the setup disposable with `docker compose down -v`.

## ADR-006 CI integration-test database

**Decision**: use Testcontainers with PostgreSQL 16 for integration tests in GitHub
Actions.

**Reason**: the tests already declare their database lifecycle and connection settings,
which keeps local and CI behavior aligned. GitHub-hosted Ubuntu runners provide Docker,
so no persistent database or reusable credentials are required. A GitHub Actions
PostgreSQL service container remains the fallback if Testcontainers proves unreliable or
unacceptably slow.

## ADR-007 Phase 4 quality and security gates

**Decision**: use OWASP Dependency-Check on the API runtime classpath with a
CVSS 7.0 blocking threshold, Gitleaks for full-history secret scanning, and
Checkstyle for static analysis.

**Reason**: the tools work with the Java/Gradle application and provide CI-visible
reports. A CVSS 7.0 threshold blocks high and critical dependency vulnerabilities
without making every lower-severity advisory a release blocker. Each tool supports
narrow, reviewed false-positive exceptions rather than disabling the entire check.

## ADR-008 Artifact Registry authentication and image tagging

**Decision**: authenticate GitHub Actions to GCP through Workload Identity
Federation using a dedicated service account with
`roles/artifactregistry.writer` scoped to the project repository. Publish every
image with the immutable Git commit SHA and also maintain `latest` as a
convenience alias; the SHA tag remains the traceability source of truth.

**Reason**: Workload Identity Federation avoids storing a long-lived GCP JSON
key in GitHub, while repository-scoped writer access follows least privilege.
The immutable SHA tag links a deployed image to its source commit and permits
reliable rollback even when the `latest` alias moves.

## ADR-009 Cloud Run health probes and autoscaling limits

**Decision**: configure Cloud Run startup and readiness probes against
`/actuator/health/readiness` and the liveness probe against
`/actuator/health/liveness`. Keep zero minimum instances, limit both the service
and each revision to one maximum instance, and allow 20 concurrent requests per
container.

**Reason**: HTTP Actuator probes validate application health more accurately
than checking only whether port 8080 is open. Separate readiness and liveness
signals avoid treating a temporary dependency-readiness problem as a dead JVM.
Zero minimum instances preserves scale-to-zero, while a maximum of one prevents
unexpected fan-out and keeps the demo workload within its intended cost and
Supabase connection limits.

## ADR-010 Terraform secret and provider boundaries

**Decision**: Terraform manages Secret Manager containers, their IAM grants,
and Cloud Run references, but never manages `google_secret_manager_secret_version`
resources or accepts database payloads as variables. Secret values are added
out of band. The Google provider authenticates through local Application
Default Credentials (ADC). Supabase remains outside the GCP Terraform boundary.

**Reason**: values passed through Terraform can be stored in local state even
when marked `sensitive`; keeping payloads out of the configuration prevents that
exposure. ADC avoids a downloaded service-account key in the repository. The
Supabase project is an external managed service and importing it would require a
separate provider and lifecycle that are not needed for the Phase 8 objective.

Secret-backed environment variables use explicit numeric versions rather than
`latest`. Cloud Run resolves them when each instance starts; pinning makes every
instance of a revision deterministic and avoids different instances resolving
different payloads during a rotation. The trade-off is intentional: rotating a
secret requires updating the Terraform reference and creating a new Cloud Run
revision, followed by health and database verification before the previous
secret version is disabled.

## ADR-011 Passive Phase 8 observability

**Decision**: retain Cloud Run's automatic request logs and built-in metrics,
then add one log-based counter for this service's HTTP 5xx responses and one
Monitoring alert policy. Sum the counter over five minutes and allow a value
above zero for 60 seconds to open an incident. Do not create an uptime check or
attach a notification channel in this phase.

**Reason**: the passive pipeline demonstrates the relationship between Logging,
a log-based metric, Monitoring, and an alert without generating synthetic
traffic that might keep Cloud Run or Supabase active. Console-only incidents are
enough for the short-lived learning environment; notification routing and more
advanced service-level monitoring remain Phase 11 work.

## ADR-012 Continuous delivery identity and Cloud Run ownership

**Decision**: keep the Artifact Registry publisher, Cloud Run deployer, and
Cloud Run runtime as three separate service accounts. GitHub Actions
authenticates the publisher and deployer through the existing repository- and
main-branch-restricted Workload Identity Federation provider; no service
account key is stored in GitHub. The publisher can write images only to the
application repository. The deployer can update the application Cloud Run
service, read its repository, and attach the existing runtime identity to a new
revision. The runtime identity remains the identity of the running application
and retains only its secret-scoped access.

Terraform owns the service's structural configuration and IAM, including
scaling, probes, resources, runtime identity, public invocation, and numeric
Secret Manager references. After the initial bootstrap, the delivery workflow
owns the selected container image, immutable revisions, temporary candidate
tags, traceability labels, and traffic allocation. Terraform therefore ignores
the image, explicit revision name, the known `commit-sha` and `managed-by`
labels, and traffic while continuing to detect other label drift and drift in
the structural fields it owns.

Every deploy targets the commit-SHA image, creates a uniquely named candidate
revision with no production traffic, smoke-tests its tagged URL, and promotes
that exact revision only after validation. Main-branch deploys are serialized,
and the temporary tag is removed after success or failure. `ci.yml` remains the
pipeline orchestrator and delegates the Cloud Run sequence to the reusable
`cloud-run-deploy.yml` workflow.

**Reason**: separate identities preserve least privilege and make each
credential's purpose auditable. Separating Terraform's stable infrastructure
ownership from the pipeline's frequently changing delivery state prevents the
two tools from repeatedly reverting each other. Candidate validation limits
the effect of a broken image, while deterministic revision names and workflow
metadata connect production traffic to the source commit and GitHub Actions
run without relying on the mutable `LATEST` target.

## ADR-013 Development and production environment separation

**Decision**: extend the Phase 9 delivery model to two logical environments in
the existing GCP project. The `develop` branch deploys automatically to the
`development` GitHub Environment and `cloud-native-api-dev`; the `main` branch
deploys to the `production` GitHub Environment and
`cloud-native-api-prod` only after a required reviewer approves the job.

Use one shared Artifact Registry repository and publisher, but create separate
Cloud Run deployer and runtime service accounts for each environment. WIF admits
only this repository's `develop` and `main` refs and maps their environment
attribute to separate service-account impersonation bindings. Each runtime can
read only its own three Secret Manager containers. GitHub Environments contain
only the non-sensitive service name and deployer email; database URL, username,
and password payloads remain exclusively in Google Secret Manager.

Use two Supabase projects rather than two schemas in one database: the existing
application project is production and the second Free Plan project is
development. Keep one GCP project instead of creating a project per environment
at this stage. Service names, identities, and secrets use explicit `-dev` and
`-prod` naming so that the environment remains visible in consoles, logs, IAM,
and Terraform plans.

Pin URL, username, and password secret versions independently for each
environment. A secret rotation remains an explicit Terraform operation that
creates a new Cloud Run revision; publishing a new image does not advance a
secret version automatically.

Retain the historical `cloud-native-api` service temporarily as a rollback
target. This is a staged replacement, not an in-place rename. Retire it only
after the new production pipeline, service, and database path are verified and
the rollback window has ended. Before removing its Terraform blocks, consolidate
all still-valid comments into the corresponding environment-aware resources;
shared publisher, registry, API, logging, and monitoring resources remain.

**Reason**: separate services and databases prevent development changes and
test data from affecting the production runtime while preserving the project's
low-cost learning constraints. Environment-scoped deployers, runtimes, secrets,
WIF bindings, and GitHub protection rules form complementary boundaries: a
workflow configuration error alone should not authorize cross-environment
deployment or secret access. A single GCP project provides less isolation than
separate projects, but avoids duplicated project-level setup and cost at the
current scale. The retained historical service provides a known rollback path
during migration instead of turning the new production URL into an irreversible
cutover.

**Migration outcome (2026-08-24)**: after automatic development delivery,
approval-gated production delivery, database isolation, secret/IAM boundaries,
and both service endpoints were verified, the rollback window was closed. The
historical service, its dedicated identities and IAM, and its three legacy
secret containers were removed through an explicitly reviewed Terraform plan.
Shared registry, publisher, WIF, APIs, logging, and Monitoring resources were
retained, and the resulting Terraform plan was a no-op.

This ADR extends ADR-012. Its separation between publisher, deployer, runtime,
Terraform ownership, and workflow-owned delivery state remains valid; those
roles are now applied independently to development and production where
appropriate.

## ADR-014 Portable structured logging and basic service observability

**Decision**: use Spring Boot's native Logstash JSON console format, renamed at
the schema boundary so `level` becomes the Cloud Logging-recognized top-level
`severity`. Keep the application provider-neutral: write to stdout and let Cloud
Run ingest the entries instead of adding a Google-specific logging appender.
Use one highest-precedence servlet filter to validate or generate
`X-Request-ID`, own the request MDC lifecycle, and emit the final status and
duration. Suppress only successful internal lifecycle-probe completion logs.

Keep Cloud Run's startup, readiness, and liveness probe paths unchanged. Add a
separate public Actuator `external` health group containing `readinessState` and
`db`, and monitor only production every 15 minutes. Add one shared dev/prod
dashboard, a low-cardinality application-ERROR log metric, and a native Cloud
Run 5xx/total-request error-rate alert grouped by `service_name`. Preserve the
Phase 8 count metric and alert unchanged. Route only the new error-rate alert to
a Terraform-managed email channel.

Distributed tracing remains deferred. Verify the alert path through a
conditionally registered development-only endpoint, enabled temporarily by a
Terraform variable that defaults to false and is structurally excluded from
production.

**Reason**: stdout JSON remains portable across container platforms while
Cloud Logging can still index severity and request context. MDC makes context
available throughout one servlet request without contaminating reused worker
threads. Separating dependency-aware external health from lifecycle probes
prevents a Supabase outage from causing restart loops. Native request metrics
represent a true error rate, while the custom log metric intentionally measures
application ERROR events. Grouping by service preserves environment isolation
without duplicating dashboards and policies. A 20% threshold over five-minute
windows, sustained for 60 seconds, is understandable for a low-traffic learning
service and treats missing scale-to-zero traffic as inactive. The restricted
fault endpoint provides real evidence without deliberately failing production.

The trade-offs are explicit: the public uptime check can wake a scaled-to-zero
instance; the email address remains in Terraform state despite being sensitive;
and without distributed tracing, cross-dependency latency diagnosis relies on
request IDs, logs, and aggregate metrics.

## ADR-015 Project cost guardrails and manual teardown

**Decision**: manage one EUR 5 monthly Cloud Billing budget through Terraform,
scoped to the single GCP project, with current-spend email thresholds at 20%,
50%, 90%, and 100%. Reuse the verified Phase 11 Monitoring email channel and do
not introduce Pub/Sub or automated billing shutdown. Keep both Cloud Run
services at zero minimum and one maximum instance. Maintain a dated inventory
of GCP and Supabase resource limits, and require a reviewed
`terraform plan -destroy` before any complete teardown.

Retain production deletion protection during normal operation. A permanent
teardown requires a separate reviewed apply that disables protection on the
production Cloud Run service and production secret containers before destroy.
Image cleanup also remains an explicit digest-level operation: current service
images and intentional rollback candidates must be identified before deletion.

**Reason**: a small budget provides an early signal without pretending to be a
hard spending cap. The EUR 1 first threshold is appropriate for an environment
expected to remain near zero, while four thresholds make escalation visible.
Manual response and teardown keep destructive authority with the operator and
preserve the phase's learning objective. Scale-to-zero limits idle compute, but
the inventory makes less obvious boundaries visible: Artifact Registry storage
can cost money while Cloud Run is idle, six active secret versions exactly use
the current free allowance, and Supabase usage is outside GCP Billing.

## ADR-016 Local Jenkins Controller and static agents

**Decision**: introduce Jenkins as a second, local CI/CD learning platform
without replacing the production GitHub Actions path. Run a persistent
Controller and two static inbound agents as peer Docker Compose services. Keep
the Controller's built-in executor count at zero. Route Gradle work to the
`build-test` label and Docker work to the `docker` label. Install the baseline
plugins in a pinned project-owned Controller image, but retain manual runtime
configuration during Phase 13; JCasC adoption remains Phase 14 work.

Use Docker-outside-of-Docker for the Docker Agent: install only the Docker CLI
in its image and mount Docker Desktop's `/var/run/docker.sock`. Add the socket's
required supplementary group only to this agent. Do not expose the socket to
the Build/Test Agent. Keep agent connection secrets in an ignored local
`jenkins/.env`, with placeholders documented in a tracked example file.

**Reason**: a Controller plus specialized agents demonstrates Jenkins's
distributed execution model and capability-based scheduling instead of hiding
both roles in one container. Inbound connections avoid SSH servers and SSH
credentials in the agents. Static agents add deliberate lifecycle management
but keep connection, identity, and recovery mechanics visible before dynamic
agents are considered. A named Controller volume makes administrative state
survive disposable container recreation.

Docker socket mounting is operationally simple and reuses Docker Desktop, but
it grants effectively root-equivalent control over the host Docker daemon. The
dedicated `docker` label, separate container, and trusted-job-only policy make
that boundary explicit; they do not remove the underlying risk. Jenkins remains
independent from Terraform: Jenkins coordinates CI/CD work, whereas Terraform
continues to own declarative cloud infrastructure.
