# Deployment and Terraform Runbook

## Responsibility split

The repository uses three related but separate processes:

1. GitHub Actions validates the application, publishes an immutable image
   through the publisher identity, and deploys it through the separate deployer
   identity for the target environment. A deployable commit on `develop`
   targets development; one on `main` targets production.
2. Terraform declares and reconciles the GCP infrastructure and IAM. After the
   initial Cloud Run bootstrap it deliberately ignores each environment's
   selected image, explicit revision name, known workflow traceability labels,
   and traffic, which belong to the delivery workflow.
3. Cloud Run starts each selected image as that environment's runtime service
   account, resolves its pinned database secret versions at container startup,
   and connects to the corresponding Supabase database.

Terraform is still executed manually: it does not watch Git commits, start
GitHub Actions, build images, or run deployments. GitHub Actions does not run
Terraform in Phase 10 and therefore cannot silently change Terraform-managed
probes, scaling, resources, runtime identity, or numeric secret references.

## Environment topology and promotion

Phase 10 separates application runtime and data while retaining one GCP project
and one Artifact Registry repository. The shared project keeps the learning
environment inexpensive; environment-specific Cloud Run services, identities,
secrets, and Supabase projects provide the required operational boundary.

| Branch | GitHub Environment | Cloud Run service | Deployment approval | Database |
| --- | --- | --- | --- | --- |
| `develop` | `development` | `cloud-native-api-dev` | automatic | dedicated development Supabase project |
| `main` | `production` | `cloud-native-api-prod` | required reviewer | dedicated production Supabase project |

The intended promotion path is:

```text
feature branch -> pull request to develop -> automatic development deployment
               -> verification -> pull request from develop to main
               -> production approval -> production deployment
```

Both GitHub Environments expose only non-sensitive deployment metadata:

| GitHub Environment | Variable | Value |
| --- | --- | --- |
| `development` | `CLOUD_RUN_SERVICE` | `cloud-native-api-dev` |
| `development` | `WIF_DEPLOYER_SERVICE_ACCOUNT` | `github-cloud-run-dev-deployer@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com` |
| `production` | `CLOUD_RUN_SERVICE` | `cloud-native-api-prod` |
| `production` | `WIF_DEPLOYER_SERVICE_ACCOUNT` | `github-cloud-run-prod-deployer@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com` |

The repository-level WIF configuration authenticates the shared image
publisher through `WIF_SERVICE_ACCOUNT` and identifies the Google WIF provider
through `WIF_PROVIDER`. Database URLs, usernames, and passwords are not
duplicated in GitHub: they remain exclusively in three environment-specific
Secret Manager containers per environment.

The historical unsuffixed `cloud-native-api` service remains available only as
a temporary rollback target while the new production path is being verified.
It is not a third logical environment and must be retired through the reviewed
migration procedure documented below.

### Identity and configuration boundaries

The shared publisher can write immutable images to the one Artifact Registry
repository but cannot deploy Cloud Run services. Deployment and runtime access
are then separated per environment:

- the development workflow may impersonate only
  `github-cloud-run-dev-deployer`; that deployer may update only
  `cloud-native-api-dev` and attach only the development runtime identity;
- the production workflow may impersonate only
  `github-cloud-run-prod-deployer`; that deployer may update only
  `cloud-native-api-prod` and attach only the production runtime identity;
- each runtime identity can read only its environment's three database
  secrets.

The WIF provider admits this repository only from `develop` and `main`. Its
mapped GitHub Environment attribute is used in the service-account IAM bindings,
so being authenticated by the provider does not by itself grant permission to
impersonate both deployers. GitHub's branch policies and production reviewer
rule provide an additional delivery gate; Google IAM remains the authorization
boundary even if a workflow is edited incorrectly.

## Prerequisites

- a pre-existing GCP project and an account with the resource-specific roles
  needed by this configuration
- Terraform 1.15.x and Google provider 7.x
- Google Cloud CLI
- Docker for local image verification
- the GitHub repository's Workload Identity Federation values
- two Supabase PostgreSQL projects, one for development and one for production,
  configured separately from Terraform

Authenticate the Google provider through Application Default Credentials (ADC):

```bash
gcloud auth application-default login
gcloud config set project <project-id>
```

ADC is the credential chain used by client libraries such as the Terraform
Google provider. It is separate from the interactive `gcloud auth login`
session and avoids storing a service-account JSON key in the repository.

## Local Terraform inputs

Create the ignored local file from the tracked example:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Set the project, region, resource names, repository and branch identity, and the
full 40-character Git commit SHA of an image that already exists in Artifact
Registry. Do not add a database URL, username, password, access token, or key.

`terraform.tfvars` answers the variable declarations in `variables.tf` before
Terraform can calculate a plan. The example is documentation only; Terraform
automatically reads the real local file, which is excluded from Git.

The legacy local `cloud-run-env.yaml` may be retained as learning evidence of
the pre-Terraform deployment, but Cloud Run no longer reads it and it must stay
untracked because it contains credentials.

## Normal Terraform workflow

```bash
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
terraform output
terraform plan
```

`init` installs the provider selected by `.terraform.lock.hcl`. `plan` compares
the configuration, Terraform state, and the current GCP objects. `apply`
executes the reviewed differences. The last plan is the convergence check: “No
changes” means that configuration, state, and remote infrastructure agree at
that moment.

Use the environment outputs instead of copying URLs or revision names from the
console:

```bash
terraform output environment_cloud_run_service_urls
terraform output environment_cloud_run_latest_ready_revisions
terraform output environment_runtime_service_account_emails
```

`environment_cloud_run_service_urls` is a map keyed by `development` and
`production`; use the matching URL to verify
`/actuator/health/readiness` after that environment has been deployed. The
singular `cloud_run_service_url` output refers to the historical service and is
retained only during the migration window.

## Staged bootstrap for an existing service

An existing manually configured service cannot be managed safely in one blind
apply. Phase 8 used this order:

1. Declare and apply the Secret Manager API, the three empty secret containers,
   the dedicated runtime service account, and the three secret-scoped accessor
   grants.
2. Add the database payloads directly to Secret Manager, outside Terraform.
3. Update the live Cloud Run service to use those secret versions and the new
   runtime identity. Verify readiness and a real database operation.
4. Declare the complete desired resource, import the existing Cloud Run service,
   and inspect the plan for replacement or credential exposure.
5. Import the remaining existing GCP resources and IAM members, then apply only
   the resources that did not exist yet.
6. Verify public access, logs, metrics, alert configuration, outputs, and a final
   no-op plan.

This sequence matters because importing Cloud Run while it still contains
plaintext variables would copy those values into local state.

## Secret payloads

Terraform deliberately creates no `google_secret_manager_secret_version`
resources. Add each value directly with `gcloud`, without printing it:

```bash
gcloud secrets versions add <secret-id> --data-file=<local-value-file>
```

Keep the value file outside the repository and remove it after use. On Windows,
avoid a PowerShell text pipeline that silently appends a newline or changes the
encoding; use an exact-byte file or another input method that preserves the
payload. Confirm the new version is enabled without displaying its contents.

The historical Cloud Run service references version `2` of:

- `cloud-native-api-database-url`
- `cloud-native-api-database-username`
- `cloud-native-api-database-password`

The Phase 10 services initially reference version `1` of their six separate
containers:

- `cloud-native-api-dev-database-url`, `-username`, and `-password`;
- `cloud-native-api-prod-database-url`, `-username`, and `-password`.

The development and production runtime service accounts receive
`roles/secretmanager.secretAccessor` only on their own three secrets. Neither
runtime receives project-wide secret access, access to the other environment's
secrets, or Artifact Registry writer permissions.

### Secret resolution and rotation

A Secret Manager secret is a stable container; each payload added to it is an
immutable numbered version. A Cloud Run revision is also immutable and records
which secret version supplies each environment variable.

Cloud Run resolves a secret-backed environment variable when an instance starts
and passes that value to the container process. It does not refresh an already
running process when the Secret Manager payload changes. Google therefore
recommends pinning environment-variable secrets to a numeric version instead of
`latest`; every service in this configuration uses explicit numeric versions.

This has two practical consequences:

- an existing instance continues using the value loaded at its startup;
- a new instance of the same revision also reads the version recorded in that
  revision, even if a later version has since been added to Secret Manager.

Each environment keeps the three version numbers independent in
`local.environments`:

```hcl
database_secret_versions = {
  database_url      = "1"
  database_username = "1"
  database_password = "1"
}
```

This prevents a password-only rotation from requiring duplicate URL and
username versions merely to make their numbers match.

Rotate one of the application secrets with this procedure:

1. Add the new payload out of band and note its numeric version without printing
   the value.
2. Confirm that the new version is enabled and that the matching external
   system change, such as a database credential rotation, is ready.
3. Change only the affected entry under `database_secret_versions` for the
   target environment in `terraform/main.tf`. The references in
   `terraform/cloud-run.tf` resolve the corresponding URL, username, or
   password entry.
4. Review `terraform plan`. The plan must contain no payload and must preserve
   the image, runtime identity, probes, scaling, and public IAM configuration.
5. Run `terraform apply`. Updating the service template creates a new Cloud Run
   revision; Terraform does not rebuild or republish the image.
6. Wait for the new revision to become ready, then select the target URL from
   `environment_cloud_run_service_urls` and verify the readiness endpoint plus
   a database-backed API operation.
7. Confirm that the latest ready revision receives 100 percent of traffic and
   that the final Terraform plan is empty.
8. Keep the previous secret version enabled for the agreed rollback window.
   Disable it only after the new revision is proven stable and rollback to a
   revision that references the old version is no longer required.

If verification fails, restore the previous numeric reference and apply again,
or use the manual Cloud Run rollback procedure below.
Never delete or disable the previous version before a working revision using the
new value has been verified.

Secret volumes have different refresh semantics and can be more suitable for
applications designed to reread files during rotation. This application expects
Spring datasource environment variables, so changing to volume mounts would be
an application and architecture change, not merely a Terraform syntax change.

The delivery workflow automates deployment of newly published container images,
but an image deployment and a secret rotation remain independent events. The
delivery pipeline does not replace a pinned secret version or resolve `latest`.
Until a dedicated rotation workflow is designed, changing the numeric version
remains an explicit, reviewed Terraform change. A future workflow may accept the
new version as an approved parameter and automate the plan, new revision,
readiness/database verification, rollback window, and retirement of the old
version; it must preserve the same safety sequence described above.

Reference: [Google Cloud Run secret configuration](https://cloud.google.com/run/docs/configuring/services/secrets).

## Importing existing infrastructure

`terraform import` does not edit a `.tf` file and does not recreate the remote
object. It writes a mapping into the local state: “this Terraform address
corresponds to this existing GCP resource ID.” The declaration must already
exist in the configuration.

Use the exact IDs for the target project. The Phase 8 mappings are recorded in
`phase-8-verification.md`; representative forms are:

```bash
terraform import google_artifact_registry_repository.application \
  projects/<project-id>/locations/<region>/repositories/<repository>

terraform import google_cloud_run_v2_service.application \
  projects/<project-id>/locations/<region>/services/<service>

terraform import google_service_account.publisher \
  projects/<project-id>/serviceAccounts/<publisher-email>

terraform import google_iam_workload_identity_pool.github_actions \
  projects/<project-number>/locations/global/workloadIdentityPools/<pool-id>

terraform import google_iam_workload_identity_pool_provider.github \
  projects/<project-number>/locations/global/workloadIdentityPools/<pool-id>/providers/<provider-id>
```

IAM member resources must also be imported individually. This project uses
additive `*_iam_member` resources so Terraform owns only the required grant and
does not replace the complete IAM policy.

## State recovery and another target project

The local state records identities and mappings; it is not the infrastructure
itself. If it is lost, GCP resources continue running, but a fresh state does
not know they exist. Recover by:

1. restoring a protected state backup if one exists, or initializing a new
   local state;
2. setting `terraform.tfvars` to the same project;
3. repeating the documented imports for every existing object and IAM member;
4. reviewing `terraform plan` until it reports no unintended creation,
   replacement, or deletion.

Never reuse the current project's state with different project variables. To
create the same topology in another project, use a separate directory/backend
or otherwise separate state, configure that project, bootstrap secret payloads
outside Terraform, and apply there. Terraform will create declared objects that
are absent from that new state and project; it will not incorrectly assume that
objects imported in the original state already exist in the new one.

## Safe destroy practice

`terraform destroy` asks Terraform to remove every managed resource in the
selected state. It is useful for proving that an intentionally disposable
environment can be cleaned up, not as a normal deployment step.

Do not run destroy against the current live project or its state. The Cloud Run
resource also has `deletion_protection = true`, so a disposable destroy test
requires an explicitly separate project/state and a reviewed configuration in
which that guard is disabled for the disposable service. Logging, Monitoring,
and Secret Manager APIs use `disable_on_destroy = false`, so removing their
Terraform resources does not disable shared project APIs.

## Artifact Registry publishing

The `image-publish` GitHub Actions job runs for deployable pushes or manual runs
on `develop` and `main`, after the build, test, dependency, secret, and
static-analysis jobs succeed. A documentation-only push is excluded before a
workflow run is created; a documentation-only pull request retains the change
classification and secret-scan checks without rebuilding an unchanged image.
The publisher job exchanges a GitHub OIDC token through Workload Identity
Federation and impersonates the shared publisher service account; no long-lived
JSON key is stored in GitHub.

The publisher has `roles/artifactregistry.writer` only on the
`cloud-native-api` repository. Each image receives its immutable commit SHA and
the `latest` convenience alias. The SHA remains the traceability and rollback
source of truth.

Phase 5 verified image tag
`a036cb9425a4d4fff1191cfdb37a523164c79706` with manifest digest
`sha256:75059f78ee5e29f92b3821fc76ccb9fec2f18cb4bd8e84971f2902a7521567b7`.

## Automated Cloud Run delivery

`.github/workflows/ci.yml` is the orchestrator: it owns the repository events,
change classification, quality gates, image publication, and the dependency
between publication and deployment. After `image-publish` succeeds, it calls
the reusable `.github/workflows/cloud-run-deploy.yml` workflow. `workflow_call`
means that the second file cannot deploy independently; it receives its GCP
resource names, selected GitHub Environment, WIF provider, and optional
controlled-failure input from the caller.

The caller maps `develop` to `development` and `main` to `production`. The
reusable deployment job declares that selected GitHub Environment through its
`environment:` key, then reads `CLOUD_RUN_SERVICE` and
`WIF_DEPLOYER_SERVICE_ACCOUNT` from the matching environment variables. The
development job starts without an approval gate. The production job must wait
for its configured reviewer, and administrators cannot bypass that rule.

Deployments are serialized independently per GitHub Environment. A running
development deployment does not block production, while two deployments to the
same environment cannot promote competing candidates concurrently.

The reusable workflow performs this sequence:

1. Exchange the GitHub OIDC identity through WIF and impersonate the dedicated
   deployer service account.
2. Select the image tagged with the full `GITHUB_SHA`; the mutable `latest` tag
   is never a deployment target.
3. Calculate a unique revision name
   `<environment-service>-sha-<short-sha>-run-<run-id>` and temporary tag
   `candidate-<short-sha>`. The run ID prevents two executions of the same
   commit from requesting the same revision name. It is intentionally omitted
   from the tag because Cloud Run limits the combined service-name and traffic-
   tag length to 46 characters. Per-environment concurrency serializes tag use,
   and the cleanup step removes the tag after each candidate attempt.
4. Deploy the candidate with `no_traffic: true`. That environment's normal
   service URL still routes 100% to its previous stable revision, while the tag
   creates a dedicated URL for the candidate. Because invocation is public at
   service level, the tagged URL is also reachable until the tag is removed.
5. Resolve that URL from Cloud Run's traffic status and smoke-test
   `/actuator/health/readiness` plus the read-only `/api/jobs` database path.
   `curl` uses finite timeouts and retries so cold start is tolerated without
   allowing the workflow to wait forever.
6. If both requests succeed, assign 100% of normal traffic to the exact tested
   revision and read the service state again to verify the assignment. The
   workflow never promotes the generic `LATEST` target.
7. Remove the candidate tag after success or failure. This removes its temporary
   URL but retains the immutable revision for inspection or rollback.

The deployment action changes only the image, revision metadata, and
traffic-owned delivery state.
It does not pass replacement environment variables, secret flags, probe flags,
scaling flags, or a different service account, so the existing
Terraform-managed revision template is inherited. The workflow summary records
the full commit SHA, immutable image reference, revision name, candidate tag,
and GitHub Actions run URL.

The manual `workflow_dispatch` input `force_smoke_failure` supports a controlled
failure exercise on `develop` or `main`. When set to `true`, the workflow first
calls the real smoke-test endpoints and then deliberately exits with an error.
The promotion step is skipped, that environment's normal traffic stays on the
previous revision, and the `always()` cleanup step removes the temporary tag.
This option is for acceptance testing, not normal deployment.

## Current Cloud Run configuration

Phase 8 adopted the historical service and created baseline revision
`cloud-native-api-00006-9pd` while migrating its datasource values to Secret
Manager references. Phase 10 provisions `cloud-native-api-dev` and
`cloud-native-api-prod` with the same Terraform-managed operational baseline,
but with separate runtime identities and separate numeric secret references.
The delivery workflow creates subsequent immutable revisions without replacing:

- the runtime service account and numeric Secret Manager references
- public invocation through the additive `allUsers` invoker member
- zero minimum and one maximum instance at service and revision level
- 20 concurrent requests per container
- startup and readiness probes on `/actuator/health/readiness`
- liveness probe on `/actuator/health/liveness`

The probes call Spring Boot Actuator endpoints implemented and exposed by the
application. Docker does not create them. An HTTP probe verifies the expected
application health response, whereas a TCP probe would only prove that a process
accepts connections on the port.

The historical service remains in Terraform during the migration window. Its
resources are deliberately kept separate from the environment `for_each`
resources so that a reviewed retirement produces an explicit deletion plan
rather than disguising the migration as a rename or state move.

## Shared environment observability

Cloud Run emits request logs automatically. The project retains one shared
log-based 5xx counter and one Monitoring alert policy rather than duplicating
them for each environment. The metric filter admits the historical,
development, and production service names; the service label in matching log
entries still identifies the source environment.

```text
Cloud Run request
  -> Logging API stores the request log
  -> the log-based metric filter selects HTTP 5xx entries for the three services
  -> Monitoring receives increments for the custom counter
  -> the alert policy evaluates the five-minute sum
  -> a value above zero for 60 seconds opens an incident
```

Logging is the source of the events, the filter decides which events count,
the log-based metric converts matching events into numeric time-series data,
and Monitoring evaluates that data. The shared alert controls cost and
configuration duplication for this learning project; when investigating an
incident, inspect the originating Cloud Run service before deciding whether
development or production is affected.

## Manual Cloud Run rollback

Cloud Run retains earlier immutable revisions and Artifact Registry retains the
corresponding commit-SHA images. A rollback does not rebuild or redeploy the old
image: it moves normal service traffic back to an already existing revision.

Set the target explicitly before issuing any rollback command:

```bash
TARGET_SERVICE="cloud-native-api-dev" # or cloud-native-api-prod
```

1. List the target environment's revisions and identify a previously verified
   revision:

   ```bash
   gcloud run revisions list \
     --service "${TARGET_SERVICE}" \
     --region europe-west8 \
     --project project-c42baf60-7736-408b-9ff
   ```

2. Review the chosen revision before changing traffic. In particular, verify
   its image, readiness, runtime service account, and secret-version references.
   A revision that uses an old disabled database secret is not a safe rollback
   target.

3. Move all normal traffic to that exact revision, never to `LATEST`:

   ```bash
   PREVIOUS_REVISION="replace-with-reviewed-revision-name"

   gcloud run services update-traffic "${TARGET_SERVICE}" \
     --region europe-west8 \
     --project project-c42baf60-7736-408b-9ff \
     --to-revisions "${PREVIOUS_REVISION}=100"
   ```

4. Confirm the effective routing and exercise readiness plus the database-backed
   read endpoint:

   ```bash
   gcloud run services describe "${TARGET_SERVICE}" \
     --region europe-west8 \
     --project project-c42baf60-7736-408b-9ff \
     --format="yaml(status.traffic)"

   SERVICE_URL="$(
     gcloud run services describe "${TARGET_SERVICE}" \
       --region europe-west8 \
       --project project-c42baf60-7736-408b-9ff \
       --format="value(status.url)"
   )"

   curl --fail "${SERVICE_URL}/actuator/health/readiness"
   curl --fail "${SERVICE_URL}/api/jobs"
   ```

Terraform ignores the workflow-owned image, revision metadata, and traffic
changes, so a later plan must not attempt to undo this rollback. The next
successful application deploy will create and validate a new revision before
moving traffic forward again.

## Phase 10 acceptance and staged legacy retirement

The configuration alone does not prove that the new delivery path works. Close
the phase through the real branch flow:

1. Open a pull request from the feature branch to `develop` and require the CI
   gates to pass. Pull-request validation does not deploy.
2. Merge into `develop`. Confirm that the automatic deployment uses the
   `development` GitHub Environment, the development deployer, and
   `cloud-native-api-dev`; verify readiness and a database-backed API request.
3. Create a uniquely identifiable test record through the development API and
   confirm through the existing application read path that it is absent from
   production. Do not inspect or copy database credentials as evidence.
4. Open a pull request from `develop` to `main` and require the same CI gates to
   pass. Merge it, confirm that the production deployment pauses for its
   required reviewer, then approve it.
5. Verify the promoted `cloud-native-api-prod` revision, readiness, the
   database-backed smoke test, serving traffic, and run summary. Record the
   sanitized GitHub Actions run links as textual evidence.
6. Move any consumer still using the historical URL to the verified production
   URL, then retain the historical service for the agreed rollback window.

Retire the historical service only after that window:

1. Classify every legacy Terraform block as historical or shared. Artifact
   Registry, the publisher, project APIs, logging metric, and alert policy are
   shared and must not be removed with the service.
2. Before deleting legacy blocks, transfer every still-valid explanatory
   comment to the corresponding environment-aware `for_each` resource. Merge
   duplicated comments into one clear explanation and remove comments that
   describe only obsolete behavior.
3. Remove the historical Cloud Run service, its public/deployer IAM members,
   and legacy runtime/deployer identities only when their remaining references
   have been checked. Confirm or deliberately disable deletion protection in a
   separate reviewed change if it is enabled.
4. Evaluate the three historical Secret Manager containers independently.
   Their retirement is not implied by deleting Cloud Run, and no payload or
   previous version should be deleted automatically.
5. Review the complete Terraform deletion plan before applying it. After the
   controlled removal, verify both environment services again and require a
   final `terraform plan` to report `No changes`.
