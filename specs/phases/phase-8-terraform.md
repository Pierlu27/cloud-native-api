# Spec: Phase 8 - Terraform (GCP Infrastructure as Code)

## 1. Goal

Replace manual GCP Console configuration with Infrastructure as Code using Terraform, so that all GCP resources required by the project (Cloud Run, Artifact Registry, IAM, Secret Manager, and monitoring resources) are defined, versioned, and reproducible from the repository. Existing resources in the current GCP project must be imported into Terraform state, while the same configuration must remain capable of creating them when applied with a separate state to an empty target project.

## 2. Scope

In scope:

- Terraform configuration for GCP resources: Artifact Registry, Cloud Run service, GitHub Workload Identity Federation, IAM roles and service accounts, Secret Manager, and Cloud Logging/Monitoring resources
- adoption of the Artifact Registry, Cloud Run, and IAM resources already provisioned manually in the current GCP project
- Terraform state management (local state for this phase, with a plan to migrate to remote state in a later iteration if needed)
- Terraform variables and outputs for environment-specific configuration (e.g. project ID, region, service name)
- `terraform init`, `plan`, and `apply` workflows documented and tested, with `destroy` documented and tested only against explicitly disposable resources or a disposable project
- removal of any Cloud SQL-related Terraform configuration from the project (since Supabase PostgreSQL is used instead of Cloud SQL)

Out of scope:

- Terraform configuration for Supabase resources (Supabase is managed via its dashboard/API; optional future improvement via the Supabase Terraform provider, but not required for this phase)
- multi-environment Terraform workspaces (e.g. separate dev/prod state files) — this phase focuses on a single environment
- advanced Terraform patterns such as modules, remote backends, or policy-as-code (these can be added later if needed)
- synthetic uptime checks, notification channels, dashboards, service-level objectives, distributed tracing, and advanced application metrics (deferred to the full observability work in Phase 12)

## 3. Functional requirements

1. A flat Terraform root module must exist in the `terraform/` directory, with at least `providers.tf`, `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`, and a non-sensitive `terraform.tfvars.example`. The current empty `modules/` placeholders must be removed; reusable child modules remain out of scope for this phase.
2. The configuration must define an Artifact Registry repository for storing Docker images. The existing repository must be imported in the current project; with a separate empty state and target project, the same resource definition must create it.
3. The configuration must define a Cloud Run service that deploys the application container from the Artifact Registry image. The existing service must be imported in the current project without destructive replacement; with a separate empty state and target project, the same resource definition must create it.
4. The configuration must define a dedicated Cloud Run runtime service account with only the permissions required by the application. It must receive `roles/secretmanager.secretAccessor` on the individual application secrets, not at project level. Image retrieval is performed by the Google-managed Cloud Run service agent and must not be conflated with the runtime service account.
5. The configuration must define Secret Manager secrets for the database URL, username, and password. Terraform must manage secret metadata and access policies, but not secret payloads or `google_secret_manager_secret_version` resources. Secret payloads must be added out-of-band with `gcloud` and referenced by Cloud Run at runtime.
6. The configuration must manage the already-enabled Cloud Logging and Cloud Monitoring APIs, define a passive log-based metric that counts HTTP 5xx responses from the `cloud-native-api` Cloud Run service, and define a Cloud Monitoring alert policy for that metric. This phase must not create a synthetic uptime check or notification channel.
7. Terraform variables must be used for all environment-specific values (project ID, region, service name, image tag), so that the same configuration can be reused across environments in the future.
8. Terraform outputs must expose key values such as the Cloud Run service URL and the Artifact Registry repository name.
9. The `terraform/` directory must not contain any Cloud SQL-related resources or modules, since the project uses Supabase PostgreSQL instead of Cloud SQL.
10. Before the existing Cloud Run service is imported, its plaintext database environment variables must be migrated to Secret Manager references so that credential values are not captured in Terraform state.
11. The existing GitHub Workload Identity Pool and OIDC provider, Artifact Registry publisher service account, repository-scoped `roles/artifactregistry.writer` grant, and repository-scoped `roles/iam.workloadIdentityUser` impersonation grant must be imported and managed by Terraform.
12. The public `allUsers` to `roles/run.invoker` grant on the Cloud Run service must be imported and managed explicitly so that public API access is reproducible.
13. `versions.tf` must constrain Terraform to a compatible 1.15 release and declare a compatible Google provider version range. The exact selected provider version and checksums must be recorded in a committed `.terraform.lock.hcl` file.
14. `providers.tf` must configure the Google provider from non-sensitive project and region variables and use Application Default Credentials. No service-account key file, access token, or credential value may be referenced from Terraform configuration.
15. `terraform.tfvars.example` must document only non-sensitive inputs. The real `terraform.tfvars`, local state, state backups, `.terraform/` directory, and saved `*.tfplan` files must remain untracked.
16. The Terraform-managed Cloud Run configuration must preserve the verified immutable commit-SHA image reference, public access, zero minimum and one maximum instance at service and revision level, concurrency of 20, startup and readiness probes on `/actuator/health/readiness`, and liveness probe on `/actuator/health/liveness`.
17. Implementation must follow a staged bootstrap: first create the missing Secret Manager prerequisites and dedicated runtime identity; then add secret payloads outside Terraform and migrate the live Cloud Run service to secret references; only after successful health and database verification may Cloud Run be imported and the complete configuration applied.

## 4. Non-functional requirements

- CI gate: no changes to the existing CI pipeline are required in this phase; Terraform is run manually for this phase (automation of Terraform in CI can be added later).
- Security: Terraform state, state backups, saved plan files, variables, and configuration files must not contain secret payloads. Marking a Terraform variable as `sensitive` only redacts command output and is not sufficient to keep its value out of state. Sensitive values must be added directly to Secret Manager outside Terraform and referenced by the Cloud Run configuration. Terraform state files and saved plan files must be excluded from version control (`.gitignore`).
- IAM safety: use narrowly scoped, additive IAM member resources where practical. Terraform must not replace an entire project or resource IAM policy merely to add one required principal.
- Observability: Cloud Run's automatically collected request logs and built-in metrics must remain available. The Terraform-managed 5xx log-based metric and alert policy must observe real traffic without generating periodic requests that could keep Cloud Run or Supabase active. Terraform apply must also produce a clear plan and execution log showing which resources are created, updated, or destroyed.
- Portability: project, region, and resource names must be supplied through variables so that the configuration can target another project with a separate state. Multi-environment state orchestration remains out of scope for this phase.
- Reproducibility: Terraform and provider compatibility must be constrained in `versions.tf`, while `.terraform.lock.hcl` must be committed to pin the exact provider build used by this repository.

## 5. Acceptance criteria

- [x] `terraform init` succeeds without errors
- [x] `terraform fmt -check` and `terraform validate` succeed for the flat root module
- [x] the bootstrap apply creates the Secret Manager API configuration, three empty secret containers, dedicated runtime service account, and secret-scoped access grants before Cloud Run import
- [x] existing Artifact Registry, Cloud Run, Workload Identity Federation, publisher service account, and IAM member grants are imported successfully into the local Terraform state
- [x] the already-enabled Cloud Logging and Cloud Monitoring project services are brought under Terraform management without disabling or interrupting telemetry
- [x] `terraform plan` after import produces a valid execution plan with no unintended deletion or replacement of the running resources
- [x] the complete `terraform apply` creates the missing monitoring resources and brings all imported resources to the declared configuration
- [x] Cloud Run service is accessible and serves the application (verified via the output URL)
- [x] Secret Manager API and the database URL, username, and password secret containers are created through Terraform
- [x] secret payloads are added with `gcloud`, are not passed through Terraform variables or resources, and do not appear in Terraform state or saved plans
- [x] Cloud Run references the Secret Manager secrets instead of plaintext database environment variables
- [x] the Secret Manager and runtime-identity migration creates a healthy Cloud Run revision while preserving the immutable image, public access, scaling limits, concurrency, and HTTP probe configuration
- [x] Cloud Run uses a dedicated runtime service account with `roles/secretmanager.secretAccessor` scoped to the individual application secrets
- [x] the Google-managed Cloud Run service agent can retrieve the Artifact Registry image without assigning image-pull permissions to the application runtime identity
- [x] GitHub Actions can still impersonate the publisher service account and push images after WIF and its IAM grants are imported
- [x] the public `roles/run.invoker` grant remains effective after import and apply
- [x] Cloud Run request logs and built-in request count and latency metrics remain visible after apply
- [x] a passive log-based metric counts HTTP 5xx responses for the `cloud-native-api` service and an alert policy can open a Monitoring incident from that metric
- [x] no uptime check or notification channel is created in this phase
- [x] a final `terraform plan` reports no changes after apply
- [x] `terraform destroy` is documented and, if tested, runs only against explicitly disposable resources or a disposable project; it must not run against the current live project
- [x] `.terraform/`, `terraform.tfstate*`, `terraform.tfvars`, and `*.tfplan` are excluded from version control, while `.terraform.lock.hcl` is committed
- [x] provider authentication succeeds through Application Default Credentials without a downloaded service-account key

## 6. Deliverables

- code: flat Terraform root-module files in `terraform/`, `terraform.tfvars.example`, and the committed `.terraform.lock.hcl`, with no Cloud SQL-related resources or empty module placeholders
- workflow: no CI/CD workflow changes in this phase (Terraform automation in CI can be added later)
- documentation: updated `docs/deployment.md` describing how to run Terraform to provision the GCP infrastructure, and updated `docs/architecture.md` reflecting the Terraform-managed infrastructure
- runbook: documented staged bootstrap, secret population, Cloud Run migration, import commands, plan review, apply, no-op verification, and state-recovery procedure

## 7. Evidence

- inventory and import commands showing how existing resource IDs map to Terraform resource addresses
- `terraform plan` output showing imported resources, resources to be created, and no unintended replacement of the running service
- `terraform apply` output showing successful resource creation
- final no-op `terraform plan` output showing that configuration, state, and GCP are aligned
- sanitized Terraform and GCP CLI evidence showing the managed Artifact Registry repository, Cloud Run service, IAM bindings, and Secret Manager secret names without exposing payloads; console screenshots are optional
- Cloud Run configuration evidence showing Secret Manager references and the dedicated runtime service account, with no credential values printed
- IAM evidence showing the separate publisher, Cloud Run service agent, runtime service account, WIF impersonation, and public invoker responsibilities
- Logging query evidence showing Cloud Run request entries, plus the Terraform-managed 5xx log-based metric and its Monitoring alert policy
- confirmation that the observability configuration generates no synthetic traffic and sends no external notifications
- Cloud Run service URL (from Terraform output) with a successful API request
- `.gitignore` entry confirming Terraform state files are excluded from version control
- version output, successful formatting and validation output, and the committed provider lock file

## 8. Risks and mitigations

- risk: Terraform state file could accidentally be committed to the repository, exposing sensitive information about the infrastructure.
  mitigation: ensure `.gitignore` includes `.terraform/`, `terraform.tfstate*`, `terraform.tfvars`, and `*.tfplan`, while intentionally allowing `.terraform.lock.hcl`; verify the rules before finalizing the phase.
- risk: passing secret payloads to Terraform, even through variables marked `sensitive`, would store those values in local state or saved plan files.
  mitigation: manage only secret containers and IAM policies with Terraform, add payloads directly with `gcloud`, and migrate Cloud Run to secret references before importing the service.
- risk: Terraform configuration could drift from the actual GCP resources if manual changes are made in the Console after `terraform apply`.
  mitigation: document that all infrastructure changes must be made through Terraform, not manually in the Console, and verify with `terraform plan` that no unexpected drift exists before applying changes.
- risk: importing the wrong GCP resource ID, or changing the target project while reusing the current state, could cause Terraform to plan destructive replacements.
  mitigation: inventory and verify every resource ID before import, inspect the complete plan before apply, and use a separate state whenever targeting another project.
- risk: using authoritative IAM policy or binding resources could remove principals that are not declared in Terraform and interrupt GitHub publishing or public API access.
  mitigation: prefer additive IAM member resources for the required grants, import each existing grant explicitly, and inspect the IAM-related plan before apply.
- risk: a periodic uptime check could keep the scale-to-zero Cloud Run service and Supabase Free project active, changing the cost and inactivity behavior accepted in Phase 7.
  mitigation: use passive log and metric processing in this phase; defer synthetic checks until their traffic and cost implications are evaluated in Phase 12.
- risk: an overly sensitive 5xx alert could open incidents for isolated transient errors and create noise.
  mitigation: use a short aggregation window with a documented threshold, keep external notification channels out of scope, and refine alert behavior with real traffic during Phase 12.
- risk: unconstrained or independently selected provider versions could produce different plans on different machines or introduce breaking schema changes.
  mitigation: declare compatible version constraints, commit `.terraform.lock.hcl`, and review provider upgrades explicitly.
- risk: losing the local Terraform state would remove Terraform's mapping to the imported GCP resources even though the resources would continue running.
  mitigation: treat the local state as an operational artifact, avoid deleting it, document the import commands needed for recovery, and evaluate a remote backend in a later phase as already planned.
- risk: Terraform could fail to apply due to missing permissions or quota limits in the GCP project.
  mitigation: perform a permission preflight for the identity running Terraform, grant only the specific resource-management permissions that are missing, and verify that the project has sufficient quota for the resources being created. Do not use `roles/editor` as the default solution.
- risk: applying the complete configuration before secret bootstrap and Cloud Run migration could copy plaintext environment values into state or propose conflicting creation of the existing service.
  mitigation: implement the configuration in the documented stages, verify the migrated live revision before import, and require a reviewed non-destructive plan before the first complete apply.
- risk: since Supabase is external to GCP, Terraform will not manage it, which could create a split in infrastructure management (GCP via Terraform, Supabase via dashboard/API).
  mitigation: document this split explicitly in `docs/architecture.md`, noting that Supabase is managed separately and that Terraform only covers GCP resources. Optionally, plan a future iteration to add the Supabase Terraform provider if desired.

## 9. Definition of done (phase)

- [x] implementation complete (Terraform configuration for all GCP resources, with no Cloud SQL-related modules)
- [x] tests pass (`terraform fmt -check`, `init`, `validate`, resource imports, `plan`, `apply`, final no-op `plan`, and any disposable-only `destroy` test all succeed)
- [x] documentation updated (`docs/deployment.md` and `docs/architecture.md` reflecting Terraform-managed infrastructure)
- [x] decisions recorded (e.g. choice to exclude Cloud SQL, decision to keep Terraform state local for now) in `docs/decisions.md` or equivalent
