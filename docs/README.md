# Documentation

This folder contains the project documentation used by the spec-driven workflow.

## Contents

- `architecture.md` - current local/cloud architecture and management boundaries
- `cost-management.md` - cost inventory, budget alerts, scale-to-zero, and safe teardown runbook
- `decisions.md` - architecture decision log
- `deployment.md` - deployment and Terraform operating runbook
- `jenkins.md` - local Jenkins Controller/Agent architecture and operating runbook
- `observability.md` - structured logs, health, metrics, dashboard, alerts, and cost boundaries
- `local-toolchain-setup.md` - local setup for Terraform and gcloud
- `security.md` - security notes and constraints
- `phase-1-verification.md` - Job API requests, errors, OpenAPI, and test evidence
- `phase-3-verification.md` - CI quality-gate and cache evidence
- `phase-4-verification.md` - Phase 4 security and quality-gate evidence
- `phase-5-verification.md` - Artifact Registry publishing and WIF evidence
- `phase-6-verification.md` - historical Cloud Run deployment evidence
- `phase-7-verification.md` - Supabase Session Pooler and persistence evidence
- `phase-8-verification.md` - Phase 8 Terraform adoption and runtime evidence
- `phase-9-verification.md` - Phase 9 continuous delivery, failure-gate, and rollback evidence
- `phase-10-verification.md` - Phase 10 environment delivery, data-isolation, and IAM-boundary evidence
- `phase-11-verification.md` - Phase 11 observability implementation and runtime verification record
- `phase-12-verification.md` - Phase 12 budget, cost inventory, scale-to-zero, and teardown dry-run evidence
- `phase-13-verification.md` - Phase 13 Jenkins Controller, agent, tooling, and persistence evidence

## Evidence organization

The phase spec is the primary source for scope, acceptance criteria, and
completion status. A separate verification document is added when the phase has
operational commands, external resource identifiers, workflow runs, or runtime
results that benefit from a longer record. Phase 2 remains documented through
its spec and the root Docker Compose instructions rather than an otherwise
duplicative verification file.

Historical verification documents preserve the resource state observed during
that phase. Later documents describe subsequent evolution; for example, the
Phase 6 revision is historical while Phase 8 records the current
Terraform-managed Cloud Run revision.

## Local setup checklist

For Phase 0, verify the local toolchain before starting implementation work:

1. Java
   ```bash
   java -version
   ```
2. Git
   ```bash
   git --version
   ```
3. Docker
   ```bash
   docker --version
   ```
4. Terraform
   ```bash
   terraform --version
   ```
5. Google Cloud CLI
   ```bash
   gcloud --version
   ```

See `local-toolchain-setup.md` for platform-specific installation guidance.
