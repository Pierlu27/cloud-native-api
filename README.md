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
- Docker (optional for container phases)

Commands:

```bash
./gradlew clean test build
./gradlew bootRun
```

Health endpoint:

```text
GET /actuator/health
```

## Documentation

- Architecture: `docs/architecture.md`
- Deployment: `docs/deployment.md`
- Security: `docs/security.md`
- Architecture decisions: `docs/decisions.md`

## Initial milestones already set

- Spring Boot bootstrap + `contextLoads` test
- Gradle Wrapper
- `docs/`, `specs/`, `terraform/`, `.github/workflows/` structure
- spec template for phase-by-phase work
