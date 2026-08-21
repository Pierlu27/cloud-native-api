# Architecture Decision Log

## ADR-001 Cloud Run

**Decision**: use Cloud Run as the initial compute layer.  
**Reason**: simpler operations, autoscaling, learning focus on CI/CD.

## ADR-002 Managed PostgreSQL provider

**Decision**: use Supabase Free PostgreSQL with the Supavisor Session Pooler.
**Reason**: keep the managed database at zero cost while separating the data
layer from Cloud Run. Cloud SQL is explicitly deferred because stopped
instances can still incur storage and IP charges. TLS is required and
credentials remain runtime-only until Secret Manager is introduced in Phase 9.

## ADR-003 Terraform

**Decision**: provision infrastructure through IaC.  
**Reason**: reproducibility, infrastructure versioning, PR-based review.

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
