# Architecture

## Local architecture

```text
Developer machine
   ├─ Spring Boot application
   └─ PostgreSQL 16 in Docker Compose
```

The local stack remains independent from the managed cloud database. Local
credentials belong in ignored environment files and are not Terraform inputs.

## Cloud architecture after Phase 11

```text
GitHub Actions
   │ short-lived OIDC token
   ▼
Workload Identity Federation
   ├─► publisher service account ──► Artifact Registry
   │      repository-scoped write       │ commit-SHA image
   │                                    ▼
   └─► deployer service account ─────► Cloud Run control plane
          service-scoped update          │ candidate, smoke test, traffic
                                         ▼
Public HTTPS ────────────────► dev/prod Cloud Run revisions
                                       │ run as separate runtime identities
                          ┌────────────┴─────────────┐
                          ▼                          ▼
                   Secret Manager          separate Supabase projects
                   environment secrets     PostgreSQL over TLS
```

GitHub Actions builds and publishes each image to Artifact Registry, then the
delivery workflow deploys that exact commit-SHA image as a zero-traffic
candidate. It tests the candidate through a temporary tagged URL and assigns it
production traffic only after both smoke tests succeed.

The publisher service account can write only to the application repository. It
does not deploy or run the application. The deployer can update only the
application service and attach its existing runtime identity; it does not
publish images or read application secrets. Cloud Run uses the dedicated runtime
service account when it executes the container, and that identity can read only
the three application secrets. Google Cloud's managed Cloud Run service agent
is responsible for retrieving the container image.

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
GitHub Actions executions, or image builds. After bootstrapping the Cloud Run
service, Terraform ignores changes to the selected image, explicit revision
name, known workflow traceability labels, and traffic because the Phase 9
workflow owns revisions and promotion; probes, scaling, resources, runtime
identity, secret references, other labels, and IAM remain Terraform-owned. Those
boundaries keep database payloads out of Terraform state and prevent
infrastructure reconciliation from undoing a successful application deployment.
The notification address is the exception: it is a sensitive Terraform input
and therefore remains in state even though it is absent from tracked files.

