# Phase 8 Terraform Verification

Verification dates: 2026-08-21 and 2026-08-22.

This document records the reproducible evidence for adopting the existing GCP
infrastructure with Terraform. It intentionally contains no secret payload,
Terraform state, saved binary plan, access token, or local variable file.

## Toolchain and configuration checks

- Terraform: `1.15.8`
- Google provider selected by `.terraform.lock.hcl`: `7.45.0`
- `terraform init`: successful
- `terraform fmt -check`: successful before and after the thematic file split
- `terraform validate -no-color`: `Success! The configuration is valid.`
- flat root module: one state and no child modules; Terraform automatically
  loads the thematic `.tf` files in `terraform/`
- final `terraform plan -no-color`: `No changes. Your infrastructure matches
  the configuration.`

The final no-op plan was repeated after moving resources out of `main.tf`.
Because their Terraform addresses did not change, no `moved` block or new
import was necessary.

## Staged bootstrap and secret migration

The first apply created the missing Secret Manager prerequisites before Cloud
Run was imported:

- `secretmanager.googleapis.com` project service declaration
- `cloud-native-api-runtime` service account
- secret containers `cloud-native-api-database-url`,
  `cloud-native-api-database-username`, and
  `cloud-native-api-database-password`
- one additive `roles/secretmanager.secretAccessor` grant per secret for the
  runtime service account

Database payloads were added directly with `gcloud`. Terraform contains no
secret-version resource and neither configuration nor state was used to pass a
payload. Cloud Run was then migrated from plaintext environment values to
Secret Manager version `2` references and the dedicated runtime identity.
Version `1` was disabled after the exact version `2` values were verified.

Revision `cloud-native-api-00006-9pd` became healthy with the same immutable
application image, HTTP probes, scaling limits, concurrency, public access, and
database connectivity. Only after that validation was the service imported.

## Terraform state inventory and imports

`terraform import` added local address-to-resource mappings; it did not recreate
or edit the remote objects. The state inventory contains these managed
addresses:

```text
google_artifact_registry_repository.application
google_artifact_registry_repository_iam_member.publisher_writer
google_cloud_run_v2_service.application
google_cloud_run_v2_service_iam_member.public_invoker
google_iam_workload_identity_pool.github_actions
google_iam_workload_identity_pool_provider.github
google_logging_metric.cloud_run_http_5xx
google_monitoring_alert_policy.cloud_run_http_5xx
google_project_service.logging
google_project_service.monitoring
google_project_service.secret_manager
google_secret_manager_secret.application["database_password"]
google_secret_manager_secret.application["database_url"]
google_secret_manager_secret.application["database_username"]
google_secret_manager_secret_iam_member.runtime_accessor["database_password"]
google_secret_manager_secret_iam_member.runtime_accessor["database_url"]
google_secret_manager_secret_iam_member.runtime_accessor["database_username"]
google_service_account.publisher
google_service_account.runtime
google_service_account_iam_member.github_publisher_impersonation
```

`data.google_project.current` is also present as a read-only data source. It
reads the project number required by WIF resource APIs; it does not create or
adopt the GCP project.

The important existing-resource ID forms used during import were:

| Terraform address | Existing GCP resource ID |
| --- | --- |
| `google_artifact_registry_repository.application` | `projects/project-c42baf60-7736-408b-9ff/locations/europe-west8/repositories/cloud-native-api` |
| `google_cloud_run_v2_service.application` | `projects/project-c42baf60-7736-408b-9ff/locations/europe-west8/services/cloud-native-api` |
| `google_service_account.publisher` | `projects/project-c42baf60-7736-408b-9ff/serviceAccounts/github-artifact-publisher@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com` |
| `google_iam_workload_identity_pool.github_actions` | `projects/630606381542/locations/global/workloadIdentityPools/github-actions` |
| `google_iam_workload_identity_pool_provider.github` | `projects/630606381542/locations/global/workloadIdentityPools/github-actions/providers/github` |
| `google_project_service.logging` | `project-c42baf60-7736-408b-9ff/logging.googleapis.com` |
| `google_project_service.monitoring` | `project-c42baf60-7736-408b-9ff/monitoring.googleapis.com` |

The publisher impersonation, repository writer, public invoker, and per-secret
access grants were imported as additive IAM member resources. This preserves
unrelated principals because Terraform does not own the complete IAM policy.

## Identity responsibilities

- GitHub-issued OIDC tokens are accepted only for repository
  `Pierlu27/cloud-native-api` on `refs/heads/main`.
- That federated principal can impersonate only the publisher service account
  through the managed `roles/iam.workloadIdentityUser` member.
- The publisher can write only to the application Artifact Registry repository.
- The Cloud Run runtime account reads only the three application secrets.
- The Google-managed Cloud Run service agent, not the runtime account, retrieves
  the image.
- `allUsers` receives only `roles/run.invoker` on this Cloud Run service.

The GitHub Actions run for main commit
`67d76ac9527f22e57be229f8ce123fa357724dd2` completed successfully on
2026-08-21: https://github.com/Pierlu27/cloud-native-api/actions/runs/32468494139.
The workflow's `image-publish` job is mandatory for a main push after all CI
gates and authenticates through the same WIF provider and publisher account.
Imports are local state operations and the final no-op plan confirms that the
remote trust and IAM grants were not changed after adoption.

## Cloud Run and public access

Terraform output:

```text
cloud_run_service_url = https://cloud-native-api-zef6s5tlmq-oc.a.run.app
artifact_registry_repository_name = cloud-native-api
```

An unauthenticated request to
`/actuator/health/readiness` through the output URL returned HTTP 200. The
public invoker member was imported and remained effective after apply and the
final no-op plan.

The adopted service preserves:

- 100% traffic to the latest ready revision
- zero minimum and one maximum instance at service and revision level
- concurrency `20`
- startup/readiness path `/actuator/health/readiness`
- liveness path `/actuator/health/liveness`
- the full immutable image SHA supplied through `image_tag`
- three Secret Manager references and no plaintext datasource values

## Logging, metric, and alert

The already-enabled `logging.googleapis.com` and `monitoring.googleapis.com`
project services were imported with `disable_on_destroy = false`. A subsequent
apply and no-op plan showed no interruption or drift.

Cloud Run request-log queries returned entries. Separate Monitoring queries for
the native `run.googleapis.com/request_count` and
`run.googleapis.com/request_latencies` metrics each returned one time series,
confirming that automatic telemetry remained available.

Terraform created the passive log-based metric
`cloud-native-api-http-5xx`. Its filter selects Cloud Run request logs for only
the `cloud-native-api` service with an HTTP status from 500 through 599. It is a
`DELTA`/`INT64` counter with no custom labels.

The Terraform configuration constructs the multiline filter with `join("\n",
...)` and `format("%s\n", ...)`. The explicit LF separators preserve the same
filter and final newline on Windows and Linux, preventing CRLF/LF differences
from appearing as a perpetual in-place update in `terraform plan`.

The alert policy `Cloud Run HTTP 5xx detected` evaluates the custom metric with:

- five-minute alignment period and `ALIGN_SUM`
- threshold greater than zero
- 60-second condition duration
- missing data treated as inactive
- one time series sufficient to trigger
- automatic incident closure after 30 minutes
- no attached notification channel

An uptime-check query returned zero resources. The project contains one
pre-existing notification channel managed outside Phase 8, but this phase did
not import, create, change, delete, or reference it. Therefore the Phase 8 alert
is console-only and the Terraform configuration generates no synthetic traffic
and no external notification.

## Apply and convergence results

The staged applies created the missing secret foundation, runtime identity,
passive metric, alert policy, and outputs while adopting the existing resources.
The output-only apply reported:

```text
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.
```

The final plan after all applies, imports, output declarations, and file
reorganization reported:

```text
No changes. Your infrastructure matches the configuration.
```

No `terraform destroy` was run against the live project. The safe disposable
procedure and Cloud Run deletion-protection requirement are documented in
`deployment.md`.

## Repository safety checks

- `.terraform/`, `terraform.tfstate*`, `terraform.tfvars`, and `*.tfplan` are
  ignored
- `.terraform.lock.hcl` is committed
- `terraform.tfvars.example` contains only non-sensitive values
- the local legacy `cloud-run-env.yaml` remains untracked and is no longer used
  by Cloud Run
- no secret payload or downloaded service-account key is part of this evidence

## Evidence format

Phase 8 uses reproducible textual evidence rather than mandatory Console
screenshots. Terraform commands, sanitized GCP CLI queries, resource IDs,
workflow links, and the public HTTP result demonstrate the configuration while
avoiding dependency on a changing Console layout. Screenshots remain optional
and must never expose secret payloads or credentials.
