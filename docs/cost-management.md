# Cost and Resource Management

This guide records the Phase 12 cost model, the resources observed on
2026-08-26, and the safe procedures for reducing or removing them. Published
prices and free allowances can change; the Google Cloud Billing report remains
the source of truth for actual charges.

## Monthly budget and alert path

Terraform manages one project-scoped Cloud Billing budget:

| Setting | Value |
|---|---|
| Display name | `Cloud Native API monthly budget` |
| Period | calendar month |
| Amount | EUR 5 |
| Spend basis | current spend after applicable credits |
| Thresholds | 20%, 50%, 90%, and 100% |
| Amounts represented | EUR 1, EUR 2.50, EUR 4.50, and EUR 5 |
| Recipient | the verified Phase 11 Monitoring email channel |

The budget is an alert, not a spending cap. Billing data can arrive after the
underlying usage, so reaching a threshold sends a notification but does not
stop Cloud Run, delete images, or disable APIs. Any budget email therefore
requires a same-day review in **Billing > Reports** and **Billing > Cost table**.

The local `billing_account_id` selects the billing account on which Terraform
creates the budget. The budget filter then limits measured spend to this
project's immutable numeric project identifier; it does not include unrelated
projects attached to the same billing account.

## Current resource and cost inventory

The inventory below distinguishes an existing resource from billable usage.
For example, a Ready Cloud Run revision is deployable metadata; it does not mean
that an instance is currently running or accumulating idle compute time.

| Component | Observed project usage | Charging boundary | Current assessment |
|---|---|---|---|
| Cloud Run | two services; 1 vCPU and 512 MiB per instance; `minScale=0`, `maxScale=1`; 11 stored revisions | with request-based billing, startup, shutdown, and request-processing time are billable; the monthly free tier currently includes 180,000 vCPU-seconds, 360,000 GiB-seconds, and 2 million requests | expected inside the free tier for didactic traffic; zero minimum instances avoids continuously billed idle capacity |
| Artifact Registry | one regional Docker repository; 28 image digests, 149 stored files/layers, approximately 1.61 GiB of physical storage; 2 digests were untagged | the first 0.5 GiB-month per billing account is free, then storage is currently approximately USD 0.10/GiB-month; layers shared by images are stored once | approximately 1.11 GiB exceeds the allowance, giving a rough USD 0.11/month storage estimate before currency conversion; this is the most likely non-zero GCP charge |
| Secret Manager | six secret containers and exactly six active automatically replicated versions | six active versions and 10,000 access operations per billing account per month are free; additional active versions currently cost USD 0.06/version/location/month | version count is exactly at the free boundary; a rotation should destroy an obsolete version after rollback safety is no longer needed |
| Cloud Logging | Cloud Run request logs and structured application logs; two low-volume log-based metrics | the first 50 GiB ingested per project per month is free; standard retention through 30 days is included in ingestion pricing | expected to remain free at current traffic; verbose logging or a request loop could change this |
| Cloud Monitoring | native Cloud Run metrics, one dashboard, two alert policies, one email channel, and one uptime check | native non-chargeable Google Cloud metrics do not consume the byte-ingestion allowance; uptime checks include 1,000,000 regional executions per project per month; alert-policy charging is announced for no earlier than 2027-09-01 | the 15-minute check across four checker regions is approximately 11,520 executions in a 30-day month and is currently inside the free allowance |
| Cloud Billing budget | one monthly budget with four thresholds | budget configuration and notification delivery do not cap usage; no project workload is started by the budget | no direct workload cost; its purpose is detection |
| IAM, service accounts, WIF, and enabled APIs | publisher, two deployers, two runtimes, one WIF pool/provider, and supporting IAM/API configuration | these control-plane objects do not create compute or storage consumption by themselves | no direct expected charge; the services they authorize can create billable usage |
| Supabase | two active Free projects, one for development and one for production | the Free plan currently allows two active projects, 500 MB database size per project, 5 GB egress, and 1 GB file storage; low-activity projects can be paused after seven days | USD 0 while within the Free plan; it is outside the GCP budget and must be checked in the Supabase dashboard separately |

Official references used for this snapshot:

- [Cloud Run pricing](https://cloud.google.com/run/pricing)
- [Artifact Registry pricing](https://cloud.google.com/artifact-registry/pricing)
- [Google Cloud Observability pricing](https://cloud.google.com/products/observability/pricing)
- [Secret Manager pricing](https://cloud.google.com/secret-manager/pricing)
- [Supabase pricing](https://supabase.com/pricing)
- [Supabase Free project pausing](https://supabase.com/docs/guides/platform/free-project-pausing)

## What does it cost to keep the project?

At the observed learning-project traffic, Cloud Run, Secret Manager, Logging,
Monitoring, IAM, and Supabase are expected to remain inside their published
free allowances. Artifact Registry is already above its storage allowance and
has an estimated storage charge of roughly USD 0.11 per month. The practical
answer is therefore **near zero, but not guaranteed to be exactly zero**.

That estimate is not evidence of the invoice. Exchange rates, taxes, billing
account-wide free-tier aggregation, delayed usage ingestion, traffic, secret
rotation, and future price changes can alter the result. Verify the current
month in the Billing Console:

1. Open **Billing > Reports** for the billing account.
2. Select the current calendar month and group costs by **Service**.
3. Filter **Projects** to this project's display name or project ID.
4. Include discounts and credits, then record both gross cost and net cost.
5. Open **Cost table** when a service total needs SKU-level detail.
6. Check Supabase usage separately for both projects because it is not included
   in GCP Billing.

The project-filtered current-month report was checked on 2026-08-26. It showed
EUR 0.05 of Cloud Run usage, EUR -0.05 of other savings, and a EUR 0.00
subtotal. No other non-zero service line was reported. The verified current
net cost is therefore zero, while the non-zero gross usage confirms why the
budget and periodic review remain useful. Artifact Registry storage remains a
forward-looking estimate and cleanup candidate even though the checked report
did not show a non-zero charge for it.

## Scale-to-zero verification

Both the Terraform service-level scaling block and each immutable revision
template declare:

```hcl
min_instance_count = 0
max_instance_count = 1
```

Live `gcloud run services describe` checks on 2026-08-26 confirmed `minScale=0`
and `maxScale=1` for `cloud-native-api-dev` and `cloud-native-api-prod`.
Consequently, no instance is intentionally kept warm when requests stop.

The production uptime check is itself a request every 15 minutes. It can wake a
scaled-to-zero service, cause a cold start, and open a Supabase connection. It
does not set a minimum instance, and its present execution volume remains far
below the Monitoring free allowance.

## Selective cleanup

### Review and remove obsolete container images

First list the images and the immutable digests currently referenced by Cloud
Run. Do not delete a digest used by either active service or retained as a
deliberate rollback candidate.

```bash
gcloud artifacts docker images list \
  europe-west8-docker.pkg.dev/PROJECT_ID/cloud-native-api \
  --include-tags

gcloud run services describe cloud-native-api-dev \
  --region=europe-west8 \
  --format="yaml(spec.template.containers[0].image,status.traffic)"

gcloud run services describe cloud-native-api-prod \
  --region=europe-west8 \
  --format="yaml(spec.template.containers[0].image,status.traffic)"
```

After resolving and reviewing one exact obsolete digest, delete only that
digest. `--delete-tags` also removes tags pointing to it:

```bash
gcloud artifacts docker images delete \
  europe-west8-docker.pkg.dev/PROJECT_ID/cloud-native-api/cloud-native-api@sha256:DIGEST \
  --delete-tags
```

Deleting an image does not remove traffic from an already running revision,
but it removes the stored artifact needed for a future deployment or rollback.
For that reason image cleanup is deliberate and is not automated in Phase 12.

### Pause without deleting infrastructure

Leaving both Cloud Run services at `minScale=0` is enough to avoid deliberately
warm instances. Stop calling the public URLs and stop manual workflow runs. If
continuous external verification is not wanted, remove the Terraform uptime
check through a reviewed configuration change and apply rather than deleting it
only in the Console and creating drift.

Supabase Free projects can be paused or can auto-pause after low activity. Use
**Supabase Dashboard > Project Settings** to pause a Free project when the data
must be retained but the project is not in use. Resume it before expecting
Cloud Run external health to report `UP`.

## Complete Terraform teardown

Complete teardown is destructive. It removes Cloud Run services, the Artifact
Registry repository and its images, secret containers and their payload
versions, identities and IAM, WIF, observability resources, and the billing
budget represented in the local state.

1. Stop deployments and confirm that no GitHub Actions run can recreate a
   revision during teardown.
2. Export any required Supabase data and preserve the ignored local
   `terraform.tfstate`, `terraform.tfvars`, and database reference files in a
   secure backup. Terraform does not manage the Supabase projects.
3. In `terraform/main.tf`, change both production values below from `true` to
   `false`:

   ```hcl
   secret_deletion_protection    = false
   cloud_run_deletion_protection = false
   ```

4. Run `terraform plan`, verify that the reviewed plan only disables those
   protections, save it, and apply that saved plan. This explicit preliminary
   apply is required because a destroy plan can list protected resources but a
   destroy operation cannot remove them while protection remains enabled.
5. Generate and inspect a fresh dry run:

   ```bash
   cd terraform
   terraform plan -destroy -out=teardown.tfplan
   terraform show -no-color teardown.tfplan
   ```

6. Confirm the expected resources and particularly the repository, six secret
   containers, two Cloud Run services, budget, dashboard, alert policies,
   uptime check, identities, and WIF resources. Never apply an old destroy plan
   after the infrastructure has changed.
7. Only when permanent removal is intended, execute a newly reviewed destroy:

   ```bash
   terraform destroy
   ```

8. Verify Cloud Run, Artifact Registry, Secret Manager, Monitoring, IAM, and
   Billing in their consoles. Project-service resources use
   `disable_on_destroy=false`, so Terraform removes them from state but leaves
   the corresponding Google APIs enabled. Enabled APIs alone do not create
   workload charges.
9. Pause or delete the two Supabase projects separately. Project deletion is
   irreversible; pausing is the recoverable choice for a temporary break.
10. Recheck **Billing > Reports** after billing ingestion has caught up. A
    teardown stops new usage but does not erase charges already incurred.

## Dry-run evidence

On 2026-08-26, the command below refreshed the real infrastructure and
successfully saved a non-destructive plan:

```bash
terraform plan -destroy -no-color -out=phase12-destroy-review.tfplan
```

Terraform reported `0 to add, 0 to change, 46 to destroy`. The review confirmed
that the plan covered the Terraform-managed application infrastructure and did
not manage either external Supabase project. The plan file is ignored by Git
and was not applied. Production Cloud Run and production secrets remain
protected; their protection must be disabled through the explicit preliminary
apply documented above before a real teardown can succeed.
