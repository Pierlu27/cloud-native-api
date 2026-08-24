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
