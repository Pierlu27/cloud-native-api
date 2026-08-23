# Spec: Phase 2 - Docker

## 1. Goal

Run the entire application stack locally through containers, packaging the Spring Boot API into an efficient Docker image and wiring it together with PostgreSQL via Docker Compose.

## 2. Scope

In scope:

- `Dockerfile` for the Spring Boot API, using a multi-stage build
- `.dockerignore`
- `docker-compose.yml` orchestrating the API and PostgreSQL
- environment variables for configuration (DB connection, ports, profiles)
- container networking between API and database
- health check for the API container
- non-root user inside the container

Out of scope:

- CI pipeline changes to build/publish the image (Phase 3/5)
- pushing the image to Artifact Registry (Phase 5)
- deployment to Cloud Run (Phase 6)
- production-specific configuration (Phase 10)

## 3. Functional requirements

1. The `Dockerfile` must use a multi-stage build: a build stage compiling the application with Gradle, and a runtime stage containing only the built artifact and a JRE.
2. The final image must run as a non-root user.
3. The `docker-compose.yml` must define at least two services: the Spring Boot API and PostgreSQL.
4. The API service must read database connection details (host, port, name, credentials) from environment variables, not hardcoded values.
5. The PostgreSQL service must persist data using a named Docker volume, so data survives container restarts.
6. The API container must expose a health check endpoint (reusing the one from Phase 1) that Docker Compose can use to determine container health.
7. The API service must depend on the database service being healthy before starting, using Compose's `depends_on` with a health condition.
8. `.dockerignore` must exclude build artifacts, `.git`, and other unnecessary files from the Docker build context.

## 4. Non-functional requirements

- CI gate: no change to the existing CI workflow is required in this phase; Docker build verification is done locally. Automated image build in CI is introduced in Phase 3/5.
- Security: the image must not run as root; no credentials must be baked into the image or the `Dockerfile`; database credentials are supplied only via environment variables at runtime.
- Observability: container health check must be in place so that `docker compose ps` reports the API as healthy once the application is ready to serve traffic.

## 5. Acceptance criteria

- [x] `docker build` completes successfully and produces a runnable image
- [x] image runs as a non-root user, verified via `docker inspect` or `whoami` inside the container
- [x] `docker compose up` starts both API and PostgreSQL successfully
- [x] API container reports healthy status once the application is ready
- [x] API is reachable on the expected port from the host machine and successfully connects to PostgreSQL running in its own container
- [x] data persists in PostgreSQL across a `docker compose down` / `docker compose up` cycle (without `-v`)
- [x] final image size is reasonable for a Spring Boot application (no unnecessary build tools or source code included in the runtime layer)

## 6. Deliverables

- code: `Dockerfile`, `.dockerignore`, `docker-compose.yml`
- workflow: none in this phase (CI integration comes later)
- documentation: updated `README.md` section describing how to build and run the application locally via Docker Compose

## 7. Evidence

- output of `docker build` showing successful multi-stage build
- output of `docker compose up` showing both services starting and reaching healthy status
- sample API request executed against the containerized application (e.g. curl against a running endpoint)
- output confirming data persistence after a compose restart cycle
- image size report (e.g. `docker images`)

## 8. Risks and mitigations

- risk: a poorly designed multi-stage build could leak build tools or source code into the final image, increasing size and attack surface.
  mitigation: keep the runtime stage minimal, copying only the built JAR and required runtime dependencies from the build stage.
- risk: hardcoding connection details or defaults suited only for local development could create confusion later when moving to Cloud SQL (Phase 7).
  mitigation: fully externalize configuration through environment variables from the start, even if the values used locally are simple defaults.
- risk: missing or misconfigured health checks could let Compose start the API before the database is ready, causing startup failures.
  mitigation: use Compose's health-based `depends_on` and verify the health check behaves as expected under a cold start.

## 9. Definition of done (phase)

- [x] implementation complete (Dockerfile, Compose setup, health checks, non-root user)
- [x] tests pass (existing unit/integration tests from Phase 1 still green; manual verification of the containerized stack)
- [x] documentation updated (README section on running via Docker Compose)
- [x] decisions recorded (if needed, e.g. base image choice, volume strategy) in `docs/decisions.md` or equivalent
