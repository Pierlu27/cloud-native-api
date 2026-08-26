# Spec: Phase 12 - Cost & Resource Management

## 1. Goal

Learn to develop without treating the cloud as an infinite, free resource, by understanding the pricing model of every GCP service used in the project, configuring budget alerts, and being able to identify and clean up resources that are not needed.

## 2. Scope

In scope:

- a GCP Billing budget with alert thresholds configured for the project
- an inventory of every billable resource in the project (Cloud Run, Artifact Registry, Cloud Logging/Monitoring, plus the externally hosted Supabase Free tier) and its pricing model
- verification that Cloud Run is configured to scale to zero (no `min-instances` keeping the service warm at a cost) unless explicitly justified
- a documented cleanup/teardown procedure for removing resources that are no longer needed (e.g. after a demo or when pausing work on the project)
- a written answer to "how much does it cost to keep this project running" and "what can I delete when I don't need it"

Out of scope:

- automated cost-control actions (e.g. auto-disabling billing via Cloud Functions triggered by budget alerts) — mentioned as a possible future improvement, not required for this phase
- cost management for the Jenkins infrastructure (Phase 13-17); Jenkins Controller/Agents are assumed to run locally or on infrastructure outside GCP billing scope for now
- multi-project or organization-level billing governance (this project uses a single GCP project)

## 3. Functional requirements

1. A GCP Billing budget must be created, scoped to the project, with a defined monthly amount reflecting the expected near-zero cost of this project.
2. The budget must have at least three alert thresholds configured (e.g. 50%, 90%, 100% of the budget), each notifying via email.
3. Cloud Run services (both development and production, per Phase 10) must have `min-instances` left at 0 (scale to zero) unless a specific, documented reason requires keeping an instance warm.
4. A cost inventory document must list every billable component in the project: Cloud Run (CPU/memory/requests), Artifact Registry (storage), Cloud Logging/Monitoring (ingestion volume beyond free tier), and Supabase (Free tier limits, not GCP-billed but still a resource constraint to track).
5. A documented teardown procedure must exist, listing the exact commands or console steps to delete or pause each billable resource (Cloud Run services, Artifact Registry images, Terraform-managed infrastructure via `terraform destroy`).
6. The teardown procedure must be tested at least once in a way that does not destroy work in progress (e.g. by running `terraform plan -destroy` to verify what would be removed, without necessarily executing a full destroy).

## 4. Non-functional requirements

- CI gate: no changes to the existing CI/CD pipeline are required in this phase.
- Security: budget alert notifications must go to an email address that is actively monitored, since a budget alert is only useful if someone actually sees it.
- Observability: it must be possible, at any time, to answer "what is currently costing money in this project" by checking the Billing Console and the cost inventory document, without needing to reverse-engineer it from Terraform files.

## 5. Acceptance criteria

- [x] a GCP budget exists for the project with a defined amount and at least three alert thresholds
- [x] budget alert notifications are configured to an actively monitored email address
- [x] `gcloud run services describe` confirms `min-instances` is 0 for both development and production Cloud Run services, unless a documented exception exists
- [x] a cost inventory document lists every billable/limited resource in the project and its relevant free tier or pricing threshold
- [x] a teardown procedure is documented step by step, covering Cloud Run, Artifact Registry, and Terraform-managed resources
- [x] `terraform plan -destroy` (or equivalent dry run) has been executed at least once and its output reviewed, confirming the teardown procedure matches what Terraform actually manages
- [x] the project's actual monthly cost, checked in the Billing Console, is verified to be at or near $0 given current usage

## 6. Deliverables

- code: no application code changes expected in this phase
- workflow: no CI/CD workflow changes in this phase
- documentation: a new `docs/cost-management.md` containing the cost inventory, the budget/alert configuration, and the teardown procedure

## 7. Evidence

- `gcloud billing budgets list` output showing the configured budget and its thresholds
- `gcloud run services describe` output confirming `min-instances=0` for each Cloud Run service
- the cost inventory document content, listing each resource and its pricing/free-tier boundary
- `terraform plan -destroy` output showing exactly which resources would be removed
- Billing Console cost report (exported as text/CSV, or the relevant billing API output) showing current spend near $0

## 8. Risks and mitigations

- risk: a budget alert only notifies after the fact — it does not stop spending, so costs could still accumulate between the alert firing and someone taking action.
  mitigation: set the lowest alert threshold conservatively (e.g. 50% of a very small budget) so there is enough lead time to react, and treat any alert as requiring same-day review, not something to defer.
- risk: forgetting to set `min-instances=0` (or setting it without realizing the cost implication) would mean paying for idle Cloud Run capacity continuously, defeating the purpose of using a serverless platform for a low-traffic learning project.
  mitigation: explicitly verify `min-instances` on every Cloud Run service as part of this phase's acceptance criteria, not just at initial deployment time.
- risk: Supabase's Free tier is not billed through GCP, so a GCP-focused budget alert would not catch Supabase-side limits being approached (storage, egress) or the project being auto-paused.
  mitigation: include Supabase Free tier limits explicitly in the cost inventory document, even though they are not part of the GCP billing budget, and check them periodically alongside GCP costs.
- risk: running `terraform destroy` for real during a demo or evaluation period would delete the whole environment, requiring a full re-provisioning before it can be shown again.
  mitigation: use `terraform plan -destroy` as a safe, non-destructive way to validate the teardown procedure, reserving the actual `destroy` command for periods when the project is genuinely paused.

## 9. Definition of done (phase)

- [x] implementation complete (budget with alert thresholds configured, `min-instances=0` verified, cost inventory and teardown procedure documented)
- [x] tests pass (`terraform plan -destroy` reviewed and matches the documented teardown procedure; current billing confirmed near $0)
- [x] documentation updated (`docs/cost-management.md` created with the cost inventory, budget configuration, and teardown steps)
- [x] decisions recorded (e.g. budget amount chosen, decision not to automate cost-control actions in this phase) in `docs/decisions.md` or equivalent
