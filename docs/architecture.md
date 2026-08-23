# Architecture

## Local architecture

```text
Developer machine
   ├─ Spring Boot application
   └─ PostgreSQL 16 in Docker Compose
```

The local stack remains independent from the managed cloud database. Local
credentials belong in ignored environment files and are not Terraform inputs.

## Cloud architecture after Phase 9

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
Public HTTPS ─────────────────────► active Cloud Run revision
                                         │ runs as runtime service account
                            ┌────────────┴─────────────┐
                            ▼                          ▼
                     Secret Manager          Supabase Session Pooler
                     database references     PostgreSQL over TLS
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
- Artifact Registry repository and its publisher and deployer grants
- runtime, publisher, and deployer service accounts
- Workload Identity Federation pool, provider, and both impersonation grants
- Secret Manager containers and secret-scoped runtime access
- Cloud Run service and public invoker grant
- passive 5xx log-based metric and Monitoring alert policy

Terraform reads the existing project metadata but does not create the GCP
project. It also does not manage secret payload versions, Supabase resources,
GitHub Actions executions, or image builds. After bootstrapping the Cloud Run
service, Terraform ignores changes to the selected image, explicit revision
name, known workflow traceability labels, and traffic because the Phase 9
workflow owns revisions and promotion; probes, scaling, resources, runtime
identity, secret references, other labels, and IAM remain Terraform-owned. Those
boundaries keep credentials out of Terraform state and prevent infrastructure
reconciliation from undoing a successful application deployment.

