# Architecture

## Local architecture

```text
Developer machine
   ├─ Spring Boot application
   └─ PostgreSQL 16 in Docker Compose
```

The local stack remains independent from the managed cloud database. Local
credentials belong in ignored environment files and are not Terraform inputs.

## Cloud architecture after Phase 8

```text
GitHub Actions
   │ short-lived OIDC token
   ▼
Workload Identity Federation ──► publisher service account
                                      │ repository-scoped image write
                                      ▼
                              Artifact Registry
                                      │ immutable image tag
                                      ▼
Public HTTPS ─────────────────────► Cloud Run
                                      │ dedicated runtime identity
                         ┌────────────┴─────────────┐
                         ▼                          ▼
                  Secret Manager          Supabase Session Pooler
                  database references     PostgreSQL over TLS
```

GitHub Actions builds and publishes images to Artifact Registry. In Phase 8,
Terraform declares the immutable image consumed by Cloud Run, but Terraform is
still run manually and does not react to a new image or Git commit. Automated
deployment of a newly published image remains part of Phase 10.

The publisher service account can write only to the application repository. It
does not run the application. Cloud Run instead uses a dedicated runtime service
account that can read only the three application secrets. Google Cloud's managed
Cloud Run service agent is responsible for retrieving the container image.

## Observability flow

```text
HTTP request
   ↓ Cloud Run serves the request and writes a request log
Cloud Logging
   ↓ the log-based metric filter selects only this service's HTTP 5xx entries
cloud-native-api-http-5xx metric
   ↓ Cloud Monitoring sums the counter over a five-minute window
Cloud Run HTTP 5xx detected alert policy
   ↓ a value above zero for 60 seconds can open an incident
Monitoring incident (Google Cloud console only)
```

Cloud Run request logs and built-in metrics are collected automatically by GCP.
The custom metric is passive: it transforms existing 5xx request logs into a
counter and does not send requests to the application. Phase 8 creates neither
an uptime check nor a notification channel, so it cannot keep the scale-to-zero
service active and sends no email or SMS.

## Terraform management boundary

The flat root module in `terraform/` manages these GCP resources:

- required Secret Manager, Logging, and Monitoring project APIs
- Artifact Registry repository and its publisher grant
- runtime and publisher service accounts
- Workload Identity Federation pool, provider, and impersonation grant
- Secret Manager containers and secret-scoped runtime access
- Cloud Run service and public invoker grant
- passive 5xx log-based metric and Monitoring alert policy

Terraform reads the existing project metadata but does not create the GCP
project. It also does not manage secret payload versions, Supabase resources,
GitHub Actions executions, image builds, or the Phase 10 deployment workflow.
Those boundaries keep credentials out of Terraform state and preserve the
separation between GCP infrastructure, the external database, and delivery.

