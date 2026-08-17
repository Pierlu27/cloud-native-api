# Cloud-Native API (Spec-Driven Learning Project)

Learning-focused project to build an **end-to-end cloud-native CI/CD pipeline** on GCP, with focus on:

- Continuous Integration and Continuous Delivery
- Infrastructure as Code (Terraform)
- Security (secrets, IAM, scanning)
- Observability (logging/monitoring)

## Working approach (spec-driven)

Each phase starts from a spec in `specs/phases/`:

1. **Scope** (what to implement)
2. **Acceptance criteria** (objective completion criteria)
3. **Evidence** (verifiable outputs)
4. **Decision log** (why this choice over alternatives)

Template: `specs/SPEC_TEMPLATE.md`

## Repository structure

```text
cloud-native-api/
├── .github/workflows/
├── docs/
├── docker/
├── specs/
├── src/
└── terraform/
```

## High-level roadmap

- Phase 0: setup + architecture
- Phase 1: backend API + test
- Phase 2: Docker + compose
- Phase 3-4: CI + quality/security gates
- Phase 5-10: artifact registry + cloud deploy + CD
- Phase 11-13: environments, observability, cost

## Local run (current bootstrap state)

Prerequisites:

- Java 25
- Docker
- PostgreSQL 16+ for local development, or Testcontainers for tests

Commands:

```bash
./gradlew clean test build
./gradlew bootRun
```

Health endpoint:

```text
GET /actuator/health
```

## Continuous Integration (GitHub Actions)

The workflow in `.github/workflows/ci.yml` runs for every push and pull request
targeting `main`. It checks out the repository, sets up Java 25 and Gradle, restores
the Gradle cache, and runs:

```bash
./gradlew clean build --no-daemon
```

This command compiles the application, runs unit tests and integration tests, and
assembles the artifact. Integration tests use Testcontainers to start an ephemeral
PostgreSQL 16 database with CI-only credentials; GitHub-hosted Ubuntu runners provide
the Docker daemon required by Testcontainers. A compilation or test failure makes the
workflow fail, so its GitHub status can be used as the pull-request quality gate.

To reproduce the same verification locally, install Java 25 and Docker, make sure the
Docker daemon is running, then execute the command above. Jenkins is introduced in a
later phase as a separate, alternative CI/CD implementation.

## Phase 1 API

Base path: `/api/jobs`

- `POST /api/jobs`
- `GET /api/jobs`
- `GET /api/jobs/{id}`
- `PUT /api/jobs/{id}`
- `DELETE /api/jobs/{id}`

API docs:

- Swagger UI: `/swagger-ui/index.html`
- OpenAPI JSON: `/v3/api-docs`

### Local database configuration

Set these environment variables when running against a local PostgreSQL instance:

```bash
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/cloud_native_api
export SPRING_DATASOURCE_USERNAME=cloud_native_api
export SPRING_DATASOURCE_PASSWORD='<your-local-password>'
```

Example PostgreSQL container:

```bash
docker run --name cloud-native-api-postgres \
  -e POSTGRES_DB=cloud_native_api \
  -e POSTGRES_USER=cloud_native_api \
  -e POSTGRES_PASSWORD='<your-local-password>' \
  -p 5432:5432 \
  -d postgres:16-alpine
```

## Run with Docker Compose

Docker Compose starts the API and its PostgreSQL dependency together.
Set local credentials using either environment variables in the shell or a local .env file (which is not stored in the image or repository), 
then build and start the stack:

```powershell
$env:POSTGRES_DB='cloud_native_api'
$env:POSTGRES_USER='cloud_native_api'
$env:POSTGRES_PASSWORD='<choose-a-local-password>'
docker compose up --build
```

The API is available at `http://localhost:8080`, with Swagger UI at
`http://localhost:8080/swagger-ui/index.html`. Use `docker compose ps` to check the
health status. PostgreSQL data is retained in the named `postgres-data` volume across
`docker compose down` and subsequent `docker compose up` runs; use `docker compose down -v`
only when intentionally discarding local data.

## Documentation

- Docs index: `docs/README.md`
- Architecture: `docs/architecture.md`
- Deployment: `docs/deployment.md`
- Security: `docs/security.md`
- Architecture decisions: `docs/decisions.md`
- Local toolchain setup (Terraform + gcloud): `docs/local-toolchain-setup.md`
- Phase 1 verification evidence: `docs/phase-1-verification.md`
- Phase 3 verification evidence: `docs/phase-3-verification.md`

## Initial milestones already set

- Spring Boot bootstrap + `contextLoads` test
- Gradle Wrapper
- `docs/`, `specs/`, `terraform/`, `.github/workflows/` structure
- spec template for phase-by-phase work
