# Cloud-Native API

Spec-driven learning project that builds a Spring Boot API and an end-to-end
cloud-native CI/CD platform on Google Cloud. The repository is intentionally
educational: every phase starts from explicit requirements, records technical
decisions, and retains text-based verification evidence.

The implementation currently covers Phases 0-15: application development,
containers, CI quality and security gates, immutable image publishing,
environment-aware continuous delivery, Terraform-managed infrastructure,
structured observability, cost control, and a local distributed Jenkins
platform configured as code with a complete continuous-integration pipeline.

## What the project demonstrates

- a Spring Boot 4 / Java 25 REST API with PostgreSQL persistence;
- local container execution with Docker Compose and PostgreSQL 16;
- unit and Testcontainers-backed integration testing;
- GitHub Actions CI with Checkstyle, Gitleaks, and OWASP Dependency-Check;
- keyless GitHub-to-GCP authentication through Workload Identity Federation;
- immutable commit-SHA images in Artifact Registry;
- separate development and production Cloud Run services and Supabase databases;
- candidate deployment, tagged-URL smoke testing, promotion, and rollback;
- least-privilege publisher, deployer, and runtime service accounts;
- Secret Manager references without secret payloads in Git or Terraform state;
- portable structured JSON logs with request correlation through MDC;
- native and log-based metrics, dashboard, alerts, email notification, and an
  external production uptime check;
- a Terraform-managed monthly billing budget, scale-to-zero configuration,
  cost inventory, and reviewed teardown procedure; and
- a persistent local Jenkins Controller configured through JCasC, a GitHub
  Multibranch job, and separate static Build/Test and Docker inbound agents;
  and
- a Jenkins CI pipeline with tests, Checkstyle, dependency scans, full-history
  secret scanning, archived reports, and GitHub commit statuses.

## Working approach

Each phase starts from a specification in `specs/phases/` and finishes only
after its implementation and evidence agree:

1. **Scope** defines what belongs to the phase.
2. **Acceptance criteria** define observable completion conditions.
3. **Implementation** changes application, workflow, infrastructure, or docs.
4. **Evidence** records commands and sanitized results; screenshots are not
   mandatory.
5. **Decision log** explains trade-offs and retained boundaries.

The reusable template is in `specs/SPEC_TEMPLATE.md`.

## Current architecture

```text
Feature branch
      │ pull request
      ▼
GitHub Actions quality and security gates
      │ merge to develop or main
      ▼
Workload Identity Federation
      ├── publisher ──► Artifact Registry commit-SHA image
      └── deployer  ──► zero-traffic Cloud Run candidate
                              │ tagged URL smoke test
                              ▼
                     environment traffic promotion
                              │
              ┌───────────────┴────────────────┐
              ▼                                ▼
   cloud-native-api-dev             cloud-native-api-prod
   development runtime              production runtime
              │                                │
              ▼                                ▼
   development secrets/DB           production secrets/DB
```

Terraform owns stable infrastructure such as services, identities, IAM,
Secret Manager containers and references, probes, scaling, observability, and
the billing budget. GitHub Actions owns changing delivery state: image builds,
explicit revisions, temporary candidate tags, smoke tests, and traffic
promotion. Supabase projects and secret payload values remain outside Terraform.

Phases 13-15 provide an independent local Jenkins Controller/Agent stack for
the second CI/CD learning track. Jenkins now runs the complete validation
pipeline, but it has no image-publishing or Cloud Run delivery pipeline yet and
does not replace the active GitHub Actions delivery path.

See [`docs/architecture.md`](docs/architecture.md) for the complete ownership
and signal-flow model.

## Repository structure

```text
cloud-native-api/
├── .github/workflows/       # CI/CD orchestration and reusable Cloud Run delivery
├── docs/                    # architecture, runbooks, decisions, and evidence
├── docker/                  # container support files
├── jenkins/                 # local Controller and static agent stack
├── specs/phases/            # phase specifications and acceptance criteria
├── src/                     # Spring Boot application and tests
├── terraform/               # GCP infrastructure as code
├── docker-compose.yml       # local API and PostgreSQL stack
└── Dockerfile               # multi-stage application image
```

## Local development

Prerequisites:

- Java 25;
- Docker with the daemon running; and
- PostgreSQL 16+, either local or supplied by Docker/Testcontainers.

Run the complete application test suite and build:

```bash
./gradlew clean build --no-daemon
```

Run against an available PostgreSQL database:

```bash
export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/cloud_native_api
export SPRING_DATASOURCE_USERNAME=cloud_native_api
export SPRING_DATASOURCE_PASSWORD='<your-local-password>'
./gradlew bootRun
```

The API is available at `http://localhost:8080`. Swagger UI is exposed at
`/swagger-ui/index.html`, OpenAPI JSON at `/v3/api-docs`, and basic Actuator
health at `/actuator/health`.

### Docker Compose

Docker Compose starts the API and PostgreSQL together. Provide local-only
credentials through the shell or an ignored `.env` file:

```powershell
$env:POSTGRES_DB='cloud_native_api'
$env:POSTGRES_USER='cloud_native_api'
$env:POSTGRES_PASSWORD='<choose-a-local-password>'
docker compose up --build
```

The named `postgres-data` volume retains database data across normal
`docker compose down` operations. Use `docker compose down -v` only when local
data should be discarded intentionally.

## Local Jenkins stack

Phases 13-15 provide a separate Compose stack with a persistent Controller, one
Build/Test Agent, and one Docker Agent. JCasC recreates the logical agents,
credentials, security settings, and GitHub Multibranch job from tracked
configuration; only secret values remain in ignored `jenkins/.env`. The
Controller coordinates jobs but has zero executors. The current Jenkins CI
pipeline routes all Gradle, quality, and security stages to `build-test`; the
`docker` label is reserved for later image-build and delivery work.

After the first-time bootstrap is complete, start all three services with:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml up -d
```

See [`docs/jenkins.md`](docs/jenkins.md) for initial setup, agent registration,
JCasC and webhook operation, pipeline stages, persistence, troubleshooting,
and the Docker socket trust boundary.

## Job API

Base path: `/api/jobs`

- `POST /api/jobs`
- `GET /api/jobs`
- `GET /api/jobs/{id}`
- `PUT /api/jobs/{id}`
- `DELETE /api/jobs/{id}`

## CI/CD flow

The `CI/CD` workflow validates pull requests targeting `develop` or `main`.
For deploy-relevant changes it runs these gates:

```text
Build and test ────────────┐
Runtime dependency scan ──┤
Build dependency scan ────┼──► all required gates pass
Secret scan ──────────────┤
Static analysis ──────────┘
```

The secret scan always examines full repository history. For a pull request
containing only `README.md`, `LICENSE`, `docs/**`, or `specs/**`, the classifier
keeps the lightweight checks but skips application build, tests, dependency
scans, and static analysis. A documentation-only push to `develop` or `main` is
ignored completely. Terraform, workflow, Docker, Gradle, and application files
are deploy-relevant and therefore run the complete pipeline.

Pull requests validate but never publish or deploy. After a deploy-relevant
merge or manual run on `develop` or `main`, the workflow:

1. rebuilds and revalidates the repository;
2. publishes both immutable `${GITHUB_SHA}` and convenience `latest` tags;
3. deploys the commit-SHA image as a zero-traffic candidate revision;
4. resolves its temporary tagged URL and executes the smoke test;
5. promotes that exact revision only when the smoke test passes; and
6. removes the temporary candidate tag after success or failure.

Jenkins provides a second, independent CI implementation. Its Multibranch job
discovers repository branches and pull requests, checks out the corresponding
commit, and runs the root `Jenkinsfile` sequentially:

```text
Checkout -> Build -> Test -> Checkstyle -> runtime dependency scan
         -> build dependency scan -> Gitleaks
```

JUnit and static-analysis results are interpreted by Jenkins, while HTML,
SARIF, JSON, and dependency reports are archived with the build. A failed
stage blocks every later stage, but its `post` publishers still preserve the
available diagnostic evidence. Jenkins then reports the final result to the
GitHub commit. It does not publish images or deploy Cloud Run in Phase 15.

| Git branch | GitHub Environment | Cloud Run service | Database | Promotion |
|---|---|---|---|---|
| `develop` | `development` | `cloud-native-api-dev` | Supabase development | automatic after successful gates and smoke test |
| `main` | `production` | `cloud-native-api-prod` | Supabase production | requires the configured production reviewer |

### Branch workflow

Feature work targets `develop`; production promotion is a separate pull request
from `develop` to `main`:

```bash
git switch develop
git pull
git switch -c feat/example-change

# edit, verify, commit, and publish
git push -u origin feat/example-change
gh pr create --base develop
gh pr checks <number> --watch

# after the feature PR and development deployment are verified
gh pr create --base main --head develop
```

The protected production GitHub Environment pauses only the production deploy
job until its reviewer approves it. Authentication uses short-lived OIDC
credentials; no downloadable GCP service-account key is stored in GitHub.

See [`docs/deployment.md`](docs/deployment.md) for bootstrap, import, secret
rotation, delivery, failure handling, and rollback procedures.

## Terraform infrastructure

The flat root module in `terraform/` manages the current GCP infrastructure.
Real variable values belong in ignored `terraform/terraform.tfvars`; the tracked
example contains placeholders only. Secret payloads are inserted out of band
and are never accepted as Terraform variables.

Typical non-destructive review:

```bash
cd terraform
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
```

Review a saved plan before applying it. Do not run `terraform destroy` against
the live learning environment casually: production Cloud Run and secret
containers have deletion protection, and the complete procedure is documented
in [`docs/cost-management.md`](docs/cost-management.md).

## Health and observability

- Cloud Run startup and readiness probes call `/actuator/health/readiness`.
- The liveness probe calls `/actuator/health/liveness` without treating a
  temporary database outage as a dead JVM.
- The public external check calls `/actuator/health/external`, which includes
  application readiness and a real database connection check.
- A request filter validates or generates `X-Request-ID`, stores request context
  in MDC, emits final status and duration, and clears the context before thread
  reuse.
- Cloud Logging receives portable JSON from stdout; Cloud Monitoring combines
  native request metrics, two log-based metrics, a shared dashboard, alert
  policies, and one 15-minute production uptime check.

See [`docs/observability.md`](docs/observability.md) for filters, metric meaning,
alert evaluation, dashboard use, and the completed controlled-error exercise.

## Cost guardrails

Both Cloud Run services use request-based billing with `minScale=0` and
`maxScale=1`. Terraform manages a EUR 5 monthly project budget with email
thresholds at 20%, 50%, 90%, and 100%. A budget sends notifications but does
not stop resources or cap spending.

The Phase 12 current-month check observed EUR 0.05 of Cloud Run usage, fully
offset by EUR -0.05 of savings, for a EUR 0.00 subtotal. Artifact Registry
storage is the main identified candidate for a future small non-zero charge;
Supabase Free limits are tracked separately because they do not appear in GCP
Billing.

See [`docs/cost-management.md`](docs/cost-management.md) for the dated resource
inventory, current pricing boundaries, selective image cleanup, and reviewed
46-resource Terraform teardown dry run.

## Documentation

- [Documentation index](docs/README.md)
- [Architecture](docs/architecture.md)
- [Deployment and Terraform runbook](docs/deployment.md)
- [Security](docs/security.md)
- [Observability](docs/observability.md)
- [Cost and resource management](docs/cost-management.md)
- [Jenkins local stack](docs/jenkins.md)
- [Architecture decision log](docs/decisions.md)
- [Local toolchain setup](docs/local-toolchain-setup.md)
- [Phase 1 verification](docs/phase-1-verification.md)
- [Phase 3 verification](docs/phase-3-verification.md)
- [Phase 4 verification](docs/phase-4-verification.md)
- [Phase 5 verification](docs/phase-5-verification.md)
- [Phase 6 verification](docs/phase-6-verification.md)
- [Phase 7 verification](docs/phase-7-verification.md)
- [Phase 8 verification](docs/phase-8-verification.md)
- [Phase 9 verification](docs/phase-9-verification.md)
- [Phase 10 verification](docs/phase-10-verification.md)
- [Phase 11 verification](docs/phase-11-verification.md)
- [Phase 12 verification](docs/phase-12-verification.md)
- [Phase 13 verification](docs/phase-13-verification.md)
- [Phase 14 verification](docs/phase-14-verification.md)
- [Phase 15 verification](docs/phase-15-verification.md)

## Roadmap status

- **Phases 0-4 complete**: setup, API, containers, CI, security, and quality.
- **Phases 5-9 complete**: Artifact Registry, Cloud Run, Supabase persistence,
  Terraform adoption, and continuous delivery.
- **Phases 10-12 complete**: environment isolation, observability, and cost
  management.
- **Phases 13-15 complete**: Jenkins Controller/Agent bootstrap, configuration
  as code, GitHub integration, and continuous integration.
- **Phases 16-17 planned**: Jenkins image delivery and later pipeline work
  extend the separate learning track without replacing the application,
  GitHub Actions delivery path, or Terraform model.
