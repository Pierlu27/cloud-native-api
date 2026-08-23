# Spec: Phase 1 - Backend Application

## 1. Goal

Build a clean, testable REST API for the Job Management domain, with a proper layered architecture, validation, error handling, persistence, and API documentation, on top of the repository bootstrapped in Phase 0.

## 2. Scope

In scope:

- `Job` entity with fields `id`, `title`, `description`, `status`, `createdAt`, `updatedAt`
- `status` enum: `PENDING`, `RUNNING`, `COMPLETED`, `FAILED`
- REST endpoints: `POST /api/jobs`, `GET /api/jobs`, `GET /api/jobs/{id}`, `PUT /api/jobs/{id}`, `DELETE /api/jobs/{id}`
- controller / service / repository layering
- DTOs and request validation
- centralized exception handling
- persistence with PostgreSQL via Spring Data JPA
- OpenAPI/Swagger documentation
- unit tests and integration tests (including Testcontainers)

Out of scope:

- containerization of the application (Phase 2)
- CI pipeline extensions beyond what already exists from Phase 0 (Phase 3)
- optional query filters such as `GET /api/jobs?status=PENDING` (nice-to-have, not required for this phase)
- deployment of any kind (Phase 6+)
- authentication/authorization on the API (not part of this project's scope per the project roadmap)

## 3. Functional requirements

1. The API must expose `POST /api/jobs` to create a new job, accepting `title` and `description`, and setting `status` to `PENDING` and `createdAt`/`updatedAt` automatically.
2. The API must expose `GET /api/jobs` to list all jobs.
3. The API must expose `GET /api/jobs/{id}` to retrieve a single job by id, returning 404 if not found.
4. The API must expose `PUT /api/jobs/{id}` to update an existing job's fields (e.g. `title`, `description`, `status`), updating `updatedAt` on every change.
5. The API must expose `DELETE /api/jobs/{id}` to remove a job, returning 404 if not found.
6. Request payloads must be validated (e.g. `title` required and non-blank); invalid requests must return a 400 with a clear error body.
7. All uncaught or expected exceptions must be handled by a centralized exception handler, returning a consistent error response shape across all endpoints.
8. Job data must be persisted in PostgreSQL through Spring Data JPA repositories.
9. The API must be documented via OpenAPI/Swagger, with all five endpoints visible and described in the generated spec/UI.

## 4. Non-functional requirements

- CI gate: `./gradlew clean build` must pass, including unit and integration tests, before this phase is considered complete.
- Security: no plaintext credentials in code or config; database connection settings for local development must be externalized (e.g. environment variables or `application.yml` profiles). Full cloud secrets management was out of scope for this phase and was subsequently completed in Phase 8.
- Observability: none required yet beyond default Spring Boot logging; structured logging and monitoring are introduced in Phase 11.

## 5. Acceptance criteria

- [x] all five endpoints implemented and manually verified (e.g. via curl or Swagger UI)
- [x] request validation returns 400 with a meaningful error message on invalid input
- [x] centralized exception handler returns consistent error responses (e.g. for 404 and 400 cases)
- [x] Job entity persisted correctly in PostgreSQL, verified via a running local database
- [x] OpenAPI/Swagger UI accessible and reflecting all endpoints
- [x] unit tests covering service layer logic
- [x] integration tests covering the API endpoints using Testcontainers with a real PostgreSQL instance
- [x] `./gradlew clean build` passes locally and on CI

## 6. Deliverables

- code: `Job` entity, DTOs, controller, service, repository, exception handler, validation annotations
- workflow: no changes expected beyond the existing Phase 0 CI workflow (build/test already covers this phase)
- documentation: OpenAPI/Swagger spec exposed by the application; updated `README.md` section describing the API and how to run it locally

## 7. Evidence

- sample requests/responses for each endpoint (e.g. curl commands or Postman collection export)
- generated OpenAPI document or endpoint inventory showing all routes
- local run output (`./gradlew clean build`) showing unit and integration tests passing
- CI run link confirming the pipeline is green with this phase's tests included

## 8. Risks and mitigations

- risk: designing the DTO/validation layer too loosely could let invalid data reach persistence.
  mitigation: enforce validation annotations on DTOs and cover invalid-input scenarios explicitly in tests.
- risk: integration tests relying on a shared or misconfigured local database could produce flaky results.
  mitigation: use Testcontainers to spin up an isolated PostgreSQL instance per test run instead of depending on a fixed local database.
- risk: keeping the domain deliberately simple (per the project roadmap) could tempt scope creep into unnecessary features.
  mitigation: stick to the five core endpoints and defer anything beyond them (e.g. filtering, pagination) to a later, explicitly scoped iteration if ever needed.

## 9. Definition of done (phase)

- [x] implementation complete (entity, DTOs, controller, service, repository, exception handling, OpenAPI docs)
- [x] tests pass (unit and integration tests green locally and on CI)
- [x] documentation updated (README API section, OpenAPI spec accessible)
- [x] decisions recorded (if needed, e.g. validation strategy, exception handling approach) in `docs/decisions.md` or equivalent
