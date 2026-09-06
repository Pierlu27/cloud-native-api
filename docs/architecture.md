# Architecture

## Local architecture

```text
Developer machine
   ├─ Spring Boot application
   ├─ PostgreSQL 16 in Docker Compose
   └─ Jenkins Compose stack
      ├─ Controller and webhook relay
      ├─ Build/Test Agent
      └─ Docker Agent with Trivy and Docker Desktop access
```

The local stack remains independent from the managed cloud database. Local
credentials, including the Jenkins publisher key, belong in ignored environment
files and are not Terraform inputs.

## Cloud architecture after Phase 16

```text
Local Jenkins ── service-account key ──► Jenkins publisher
                                               │ repository writer
                                               ▼
Artifact Registry / cloud-native-api-dev:<SHA> + latest
             │ published only; Phase 17 adds development deployment
Public HTTPS ──► development Cloud Run keeps its last healthy revision

GitHub Actions ── short-lived OIDC ──► Workload Identity Federation
             ├─► GitHub publisher ──► Artifact Registry / cloud-native-api-prod
             └─► production deployer ──► Cloud Run production control plane
                                              │ candidate, smoke test, traffic
                                              ▼
Public HTTPS ─────────────────────────► production Cloud Run revisions
                                              │ production runtime identity
                                              ▼
                                   Secret Manager ──► Supabase production

Development Cloud Run keeps its last healthy revision during the Phase 16-to-17
transition; its runtime identity, secrets, and Supabase database remain separate.
```

Jenkins builds and scans every trusted internal branch or pull request, but
publishes `cloud-native-api-dev` only for a clean direct `develop` build. Phase
16 does not deploy that package, so the last healthy development revision stays
active until Phase 17 introduces Jenkins delivery.

GitHub Actions retains its validation gates for `develop` and `main`, but only a
clean direct `main` run publishes `cloud-native-api-prod` and invokes the
production delivery workflow. That workflow deploys the exact commit-SHA image
as a zero-traffic candidate, tests its tagged URL, and assigns production
traffic only after both smoke tests succeed.

The Jenkins and GitHub publisher service accounts can write only to the shared
application repository; package naming separates their operational ownership
but not their repository-level IAM permissions. Neither publisher deploys or
runs the application. The production deployer can update only its Cloud Run
service and attach its existing runtime identity; it does not publish images or
read application secrets. Cloud Run uses the dedicated environment runtime
account when it executes a container, and that identity can read only its three
application secrets. Google Cloud's managed Cloud Run service agent retrieves
the selected container image.

## Observability flow

```text
Client request ──► Cloud Run ──► request filter/MDC ──► application
       │                              │                      │
       │                              └─ request context     └─ health + DB
       ▼
Cloud Run request metrics             structured JSON to stdout
       │                                      │
       └──────────────────┬───────────────────┘
                          ▼
              Cloud Logging / Monitoring
                 │        │         │
                 ▼        ▼         ▼
              metrics  dashboard  alert policies ──► email channel

Google uptime check ── every 15 min ──► prod /actuator/health/external
```

Cloud Run collects request logs and platform metrics automatically. Spring emits
portable Logstash JSON to stdout; Cloud Logging recognizes its top-level
`severity` and keeps the remaining fields searchable. The request filter uses
MDC to add one request identifier, method, and path to all logs written while a
request is processed, then removes that context before the worker thread is
reused.

The Phase 8 5xx counter and console-only count alert remain unchanged. Phase 11
adds an application-ERROR counter, a native 5xx/total-request ratio, a shared
dev/prod dashboard, an email-backed error-rate alert, and one production uptime
check. Unlike passive metrics, the uptime check sends a real request and can
wake a service that has scaled to zero. See `observability.md` for the complete
signal flow and operating guide.

## Terraform management boundary

The flat root module in `terraform/` manages these GCP resources:

- required Secret Manager, Logging, and Monitoring project APIs
- Artifact Registry repository and its publisher and deployer grants
- runtime, publisher, and deployer service accounts
- Workload Identity Federation pool, provider, and both impersonation grants
- Secret Manager containers and secret-scoped runtime access
- Cloud Run service and public invoker grant
- preserved Phase 8 5xx log-based metric and count alert policy
- Phase 11 application-error metric, native error-rate alert, email channel,
  production uptime check, and shared observability dashboard

Terraform reads the existing project metadata but does not create the GCP
project. It also does not manage secret payload versions, Supabase resources,
GitHub Actions executions, Jenkins jobs, or image builds. When creating Cloud
Run services in a new target configuration, Terraform maps development to
`cloud-native-api-dev` and production to `cloud-native-api-prod`. After that
bootstrap it ignores changes to the selected image, explicit revision name,
known workflow traceability labels, and traffic because the delivery layer owns
revision and promotion state. Probes, scaling, resources, runtime identity,
secret references, other labels, and IAM remain Terraform-owned. Those
boundaries keep database payloads out of Terraform state and prevent
infrastructure reconciliation from undoing a successful application deployment.
The notification address is the exception: it is a sensitive Terraform input
and therefore remains in state even though it is absent from tracked files.

