# Architecture Decision Log

## ADR-001 Cloud Run

**Decision**: use Cloud Run as the initial compute layer.  
**Reason**: simpler operations, autoscaling, learning focus on CI/CD.

## ADR-002 Cloud SQL

**Decision**: use Cloud SQL PostgreSQL.  
**Reason**: separate compute and data layers, practice with a managed DB.

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

**Decision**: use OWASP Dependency-Check with a CVSS 7.0 blocking threshold,
Gitleaks for full-history secret scanning, and Checkstyle for static analysis.

**Reason**: the tools work with the Java/Gradle application and provide CI-visible
reports. A CVSS 7.0 threshold blocks high and critical dependency vulnerabilities
without making every lower-severity advisory a release blocker. Each tool supports
narrow, reviewed false-positive exceptions rather than disabling the entire check.
