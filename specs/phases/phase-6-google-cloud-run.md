# Spec: Phase 6 - Google Cloud Run with Free PostgreSQL

## 1. Goal

Deploy the containerized application to Google Cloud Run, making the API publicly reachable over HTTPS, sourcing the image from Artifact Registry.

## 2. Scope

In scope:

- Cloud Run service creation and configuration
- deployment of the image published in Phase 5 to Cloud Run
- environment variable configuration on the Cloud Run service
- health check configuration
- public HTTPS endpoint exposure
- connection to a free external PostgreSQL provider (Supabase Free)

Out of scope:

- Cloud SQL integration (deferred because it is not zero-cost)
- Terraform-managed provisioning of Cloud Run (Phase 8 formalizes this as IaC; this phase can use manual/CLI setup)
- CI/CD automation of the deployment step itself (Phase 10 wires this into the pipeline)
- multi-environment separation (Phase 11)

## 3. Functional requirements

1. A Cloud Run service must be created, configured to pull the application image from the Artifact Registry repository set up in Phase 5.
2. The Cloud Run service must expose the application over a public HTTPS endpoint.
3. The service must be configured with the application's required environment variables (`SPRING_DATASOURCE_URL`, `SPRING_DATASOURCE_USERNAME`, `SPRING_DATASOURCE_PASSWORD`, and active profile where needed).
4. The service must use the health check endpoint from Phase 1 to determine container readiness/liveness.
5. The service must support automatic revisions: deploying a new image version must create a new revision without manual intervention beyond the deploy command.
6. The service must be configured with reasonable autoscaling settings (e.g. min/max instance counts) appropriate for a small demo workload.

## 4. Non-functional requirements

- CI gate: not applicable directly in this phase; deployment is performed manually/via CLI for now and automated in Phase 10.
- Security: the Cloud Run service must not expose any unnecessary ports or services; only the application's HTTP(S) port should be reachable.
- Observability: basic Cloud Run request/latency metrics must be visible in the GCP console after deployment, even though full monitoring setup is deferred to Phase 12.

## 5. Acceptance criteria

- [x] Cloud Run service successfully deployed using the image from Artifact Registry
- [x] Supabase Free PostgreSQL connection verified locally through the application
- [x] application reachable via a public HTTPS endpoint
- [x] health check endpoint correctly used by Cloud Run to determine container health
- [x] environment variables correctly applied and verified (e.g. via a request that depends on configuration)
- [x] a new image push results in a new Cloud Run revision after redeployment
- [x] basic request metrics visible in the Cloud Run console

## 6. Deliverables

- code: no application code changes expected in this phase
- workflow: none in this phase (manual/CLI deployment; automation comes in Phase 10)
- documentation: updated `docs/deployment.md` describing Cloud Run service configuration and how to deploy manually

## 7. Evidence

Detailed verification: [`docs/phase-6-verification.md`](../../docs/phase-6-verification.md).

Completion record updated on 2026-08-21:

- public HTTPS URL:
  `https://cloud-native-api-630606381542.europe-west8.run.app`;
- `/actuator/health`, `/actuator/health/liveness`, and
  `/actuator/health/readiness` returned `UP` against the public service;
- active revision `cloud-native-api-00005-knj` serves 100 percent of traffic
  using the immutable Artifact Registry image tag
  `d893465c3bb43001fe8d9c420263a4e7b89a4292`;
- Cloud Run uses an HTTP startup probe and readiness probe on
  `/actuator/health/readiness` and an HTTP liveness probe on
  `/actuator/health/liveness`, all on port `8080`;
- service-level and revision-level maximum instance counts are both `1`, the
  minimum remains `0`, and container concurrency is `20`;
- revision history contains both `cloud-native-api-00004-2p6` and
  `cloud-native-api-00005-knj`, confirming that an update creates a new
  revision while preserving the previous one for rollback;
- public Swagger CRUD requests were previously verified against the Supabase
  database, demonstrating that runtime datasource configuration is effective;
- successful public requests populate Cloud Run's native request count and
  latency metrics.

## 8. Risks and mitigations

- risk: misconfigured environment variables on Cloud Run could cause the application to fail to start, with unclear error messages.
  mitigation: verify environment variable configuration against the working local Docker Compose setup from Phase 2 before deploying.
- risk: an overly permissive autoscaling configuration could lead to unexpected costs.
  mitigation: set conservative min/max instance limits appropriate for a demo workload, revisited in Phase 13 (Cost & Resource Management).
- risk: the health check misconfigured could cause Cloud Run to mark healthy containers as unhealthy, causing repeated restarts.
  mitigation: test the health check endpoint manually before wiring it into Cloud Run's readiness/liveness configuration.

## 9. Definition of done (phase)

- [x] implementation complete (Cloud Run service deployed, configured, and publicly reachable)
- [x] tests pass (manual verification of API endpoints against the live Cloud Run URL)
- [x] documentation updated (`docs/deployment.md` with Cloud Run configuration details)
- [x] decisions recorded (if needed, e.g. autoscaling limits, environment variable strategy) in `docs/decisions.md` or equivalent
