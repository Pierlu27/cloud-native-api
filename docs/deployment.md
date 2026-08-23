# Deployment and Terraform Runbook

## Responsibility split

The repository uses three related but separate processes:

1. GitHub Actions validates the application, publishes an immutable image
   through the publisher identity, and deploys it through the separate deployer
   identity when a deployable commit reaches `main`.
2. Terraform declares and reconciles the GCP infrastructure and IAM. After the
   initial Cloud Run bootstrap it deliberately ignores the selected image and
   traffic, which belong to the delivery workflow.
3. Cloud Run starts the selected image as the runtime service account, resolves
   the pinned database secret versions at container startup, and connects to the
   external Supabase database.

Terraform is still executed manually: it does not watch Git commits, start
GitHub Actions, build images, or run deployments. GitHub Actions does not run
Terraform in Phase 9 and therefore cannot silently change Terraform-managed
probes, scaling, resources, runtime identity, or numeric secret references.

## Prerequisites

- a pre-existing GCP project and an account with the resource-specific roles
  needed by this configuration
- Terraform 1.15.x and Google provider 7.x
- Google Cloud CLI
- Docker for local image verification
- the GitHub repository's Workload Identity Federation values
- a Supabase PostgreSQL project configured separately from Terraform

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

Use the declared output instead of copying a URL from the console:

```bash
SERVICE_URL="$(terraform output -raw cloud_run_service_url)"
curl "$SERVICE_URL/actuator/health/readiness"
```

The current Phase 8 output resolves to the public Cloud Run service, whose
readiness endpoint returned HTTP 200 after the final no-op plan.

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

Cloud Run currently references version `2` of:

- `cloud-native-api-database-url`
- `cloud-native-api-database-username`
- `cloud-native-api-database-password`

The runtime service account receives `roles/secretmanager.secretAccessor` on
each of these secrets individually. It does not receive project-wide secret
access or Artifact Registry writer permissions.

### Secret resolution and rotation

A Secret Manager secret is a stable container; each payload added to it is an
immutable numbered version. A Cloud Run revision is also immutable and records
which secret version supplies each environment variable.

Cloud Run resolves a secret-backed environment variable when an instance starts
and passes that value to the container process. It does not refresh an already
running process when the Secret Manager payload changes. Google therefore
recommends pinning environment-variable secrets to a numeric version instead of
`latest`; the current Terraform configuration pins version `2`.

This has two practical consequences:

- an existing instance continues using the value loaded at its startup;
- a new instance of the same revision also reads version `2`, even if version
  `3` has since been added to Secret Manager.

Rotate one of the application secrets with this procedure:

1. Add the new payload out of band and note its numeric version without printing
   the value.
2. Confirm that the new version is enabled and that the matching external
   system change, such as a database credential rotation, is ready.
3. Change only the affected `version` reference in `terraform/cloud-run.tf`
   from the previous number to the new number.
4. Review `terraform plan`. The plan must contain no payload and must preserve
   the image, runtime identity, probes, scaling, and public IAM configuration.
5. Run `terraform apply`. Updating the service template creates a new Cloud Run
   revision; Terraform does not rebuild or republish the image.
6. Wait for the new revision to become ready, then verify the readiness endpoint
   and a database-backed API operation through `cloud_run_service_url`.
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

Phase 9 automates deployment of newly published container images, but an image
deployment and a secret rotation remain independent events. The delivery
pipeline does not replace a pinned secret version or resolve `latest`.
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

The `image-publish` GitHub Actions job runs for deployable pushes to `main`, or
for an explicitly requested manual main-branch exercise, after the build, test,
dependency, secret, and static-analysis jobs succeed. A documentation-only
merge is excluded before a workflow run is created. The job exchanges a GitHub
OIDC token through Workload Identity Federation and impersonates the dedicated
publisher service account; no long-lived JSON key is stored in GitHub.

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
resource names, deployer identity, WIF provider, and optional controlled-failure
input from the caller.

The reusable workflow performs this sequence:

1. Exchange the GitHub OIDC identity through WIF and impersonate the dedicated
   deployer service account.
2. Select the image tagged with the full `GITHUB_SHA`; the mutable `latest` tag
   is never a deployment target.
3. Calculate a unique revision name
   `cloud-native-api-sha-<short-sha>-run-<run-id>` and temporary tag
   `candidate-<short-sha>-<run-id>`. The run ID prevents two executions of the
   same commit from requesting the same revision name.
4. Deploy the candidate with `no_traffic: true`. The normal service URL still
   routes 100% to the previous stable revision, while the tag creates a
   dedicated URL for the candidate. Because invocation is public at service
   level, the tagged URL is also reachable until the tag is removed.
5. Resolve that URL from Cloud Run's traffic status and smoke-test
   `/actuator/health/readiness` plus the read-only `/api/jobs` database path.
   `curl` uses finite timeouts and retries so cold start is tolerated without
   allowing the workflow to wait forever.
6. If both requests succeed, assign 100% of normal traffic to the exact tested
   revision and read the service state again to verify the assignment. The
   workflow never promotes the generic `LATEST` target.
7. Remove the candidate tag after success or failure. This removes its temporary
   URL but retains the immutable revision for inspection or rollback.

The deployment action changes only the image and traffic-owned delivery state.
It does not pass replacement environment variables, secret flags, probe flags,
scaling flags, or a different service account, so the existing
Terraform-managed revision template is inherited. The workflow summary records
the full commit SHA, immutable image reference, revision name, candidate tag,
and GitHub Actions run URL.

The manual `workflow_dispatch` input `force_smoke_failure` supports a controlled
failure exercise. When set to `true`, the workflow first calls the real smoke
test endpoints and then deliberately exits with an error. The promotion step is
skipped, normal traffic stays on the previous revision, and the `always()`
cleanup step removes the temporary tag. This option is for acceptance testing,
not normal deployment.

## Current Cloud Run configuration

Phase 8 adopted the existing service and created baseline revision
`cloud-native-api-00006-9pd` while migrating the datasource values to Secret
Manager references. Phase 9 creates subsequent immutable revisions without
replacing the following Terraform-managed settings:

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

## Manual Cloud Run rollback

Cloud Run retains earlier immutable revisions and Artifact Registry retains the
corresponding commit-SHA images. A rollback does not rebuild or redeploy the old
image: it moves normal service traffic back to an already existing revision.

1. List the available revisions and identify a previously verified revision:

   ```bash
   gcloud run revisions list \
     --service cloud-native-api \
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

   gcloud run services update-traffic cloud-native-api \
     --region europe-west8 \
     --project project-c42baf60-7736-408b-9ff \
     --to-revisions "${PREVIOUS_REVISION}=100"
   ```

4. Confirm the effective routing and exercise readiness plus the database-backed
   read endpoint:

   ```bash
   gcloud run services describe cloud-native-api \
     --region europe-west8 \
     --project project-c42baf60-7736-408b-9ff \
     --format="yaml(status.traffic)"

   SERVICE_URL="$(
     gcloud run services describe cloud-native-api \
       --region europe-west8 \
       --project project-c42baf60-7736-408b-9ff \
       --format="value(status.url)"
   )"

   curl --fail "${SERVICE_URL}/actuator/health/readiness"
   curl --fail "${SERVICE_URL}/api/jobs"
   ```

Terraform ignores workflow-owned image and traffic changes, so a later plan
must not attempt to undo this rollback. The next successful application deploy
will create and validate a new revision before moving traffic forward again.
