# Phase 12 Cost and Resource Management Verification

Infrastructure and inventory verification date: 2026-08-26.

This document records sanitized text evidence for the project budget,
scale-to-zero configuration, cost inventory, and non-destructive teardown test.
Console screenshots are not mandatory. The monitored email address, ignored
Terraform inputs and state, secret payloads, and database connection strings
must not be included.

## Applied budget

Terraform enabled `billingbudgets.googleapis.com` and created the project-scoped
budget `Cloud Native API monthly budget`. The applied result reported two
resources added and no existing resources changed or destroyed.

The direct verification command was:

```bash
gcloud billing budgets list \
  --billing-account=BILLING_ACCOUNT_ID \
  --format=json
```

The response confirmed:

- EUR 5 per calendar month;
- project filter `projects/630606381542`;
- all applicable credits included;
- current-spend thresholds `0.20`, `0.50`, `0.90`, and `1.00`;
- the existing Phase 11 Monitoring notification channel; and
- default billing-account IAM recipients disabled, preventing duplicate routes.

The budget resource ID is intentionally omitted because its display name and
configuration are sufficient operational evidence. The notification address is
also omitted even though the associated channel is verified and monitored.

After apply, Terraform reported:

```text
No changes. Your infrastructure matches the configuration.
```

## Scale-to-zero evidence

The Terraform configuration declares zero minimum and one maximum instance at
both service and revision-template level. Live service descriptions for
`cloud-native-api-dev` and `cloud-native-api-prod` confirmed template
annotations equivalent to:

```text
autoscaling.knative.dev/minScale = 0
autoscaling.knative.dev/maxScale = 1
```

The service-level API omitted the zero minimum because zero is its default and
reported the one-instance maximum. Both environments therefore satisfy the
scale-to-zero requirement. Ready revisions do not imply continuously running
instances.

## Resource inventory evidence

The 2026-08-26 inventory found:

- two Cloud Run services, with seven development and four production revisions;
- six Secret Manager containers with one enabled version each;
- one Artifact Registry Docker repository containing 28 image digests, of
  which two were untagged, and approximately 1.61 GiB of deduplicated physical
  storage across 149 repository files/layers;
- two user-defined log-based metrics;
- one Monitoring dashboard, two alert policies, one email channel, and one
  15-minute production uptime check; and
- two external Supabase Free projects, one per application environment.

The cost interpretation and current official pricing boundaries are recorded
in `docs/cost-management.md`. Artifact Registry is the only component observed
above its published free storage allowance; its estimated excess-storage cost
is roughly USD 0.11 per month. This is an estimate, not the billing report.

## Non-destructive teardown evidence

The required safe teardown test used:

```bash
terraform plan -destroy -no-color -out=phase12-destroy-review.tfplan
```

Terraform refreshed the real remote objects and reported:

```text
Plan: 0 to add, 0 to change, 46 to destroy.
```

The plan included the two Cloud Run services, Artifact Registry repository,
budget, six secret containers, service accounts and IAM, WIF, log metrics,
Monitoring resources, and other Terraform-managed dependencies. It did not
include the Supabase projects because they are outside the Terraform boundary.

The saved plan is ignored by Git and was not applied. A plan can describe the
deletion of protected production resources, but a real destroy cannot complete
while their deletion protection remains enabled. The complete runbook therefore
requires a separate reviewed apply that disables those protections before
creating a fresh destroy plan.

## Actual billing evidence

The authenticated Billing Console was checked on 2026-08-26 for the current
calendar month with the project selected. It reported:

```text
Cloud Run usage       EUR  0.05
Other savings         EUR -0.05
Subtotal              EUR  0.00
```

No other non-zero service line was reported. The gross Cloud Run usage was
fully offset by the applied savings, so the verified current net project cost
is zero and satisfies the expected near-zero operating cost. Artifact Registry
storage remains documented as a possible future charge based on measured
storage and published allowances; it was not presented as a non-zero charge in
this report.
