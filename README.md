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

## Documentation

- Docs index: `docs/README.md`
- Architecture: `docs/architecture.md`
- Deployment: `docs/deployment.md`
- Security: `docs/security.md`
- Architecture decisions: `docs/decisions.md`
- Local toolchain setup (Terraform + gcloud): `docs/local-toolchain-setup.md`
- Phase 1 verification evidence: `docs/phase-1-verification.md`

## Initial milestones already set

- Spring Boot bootstrap + `contextLoads` test
- Gradle Wrapper
- `docs/`, `specs/`, `terraform/`, `.github/workflows/` structure
- spec template for phase-by-phase work
