# Spec: Phase 9 - Continuous Delivery (GitHub Actions)

## 1. Goal

Complete the GitHub Actions pipeline by automating deployment to Cloud Run after a successful build, test, security scan, and image push, so that every successful push to the main branch, including a pull-request merge, results in a new immutable revision without manual deployment commands. The revision must receive production traffic only after it passes validation.

Documentation-only changes are not deployable application changes: they must preserve the required pull-request status check without running the expensive build, dependency scan, static analysis, image-publish, or deployment stages, and must not create a redundant Cloud Run revision after merge. Secret scanning remains mandatory because credentials can be leaked in documentation as well as code.

## 2. Scope

In scope:

- extending the existing GitHub Actions pipeline (build, test, security scan, Docker build, image push from Phase 3-5) with an automated deployment stage to Cloud Run, while keeping `ci.yml` as the orchestrator and isolating the Cloud Run steps in a reusable `workflow_call` workflow
- authenticating GitHub Actions to GCP using Workload Identity Federation (no long-lived service account keys)
- deploying using immutable image tags (commit SHA), never `latest`
- deploying new revisions with `--no-traffic` and a temporary revision tag first, followed by an explicit traffic promotion step, to keep validation and rollback simple
- a documented, tested rollback procedure using Cloud Run revisions
- defining a clear ownership boundary: Terraform manages the service's structural configuration and IAM, while GitHub Actions manages the deployed image, revisions, and traffic after the initial infrastructure bootstrap
- classifying documentation-only changes so they do not build or deploy an unchanged application while required pull-request checks still resolve successfully and secret scanning remains active

Out of scope:

- gradual/canary traffic splitting automation (a possible future improvement; this phase only requires the capability to shift traffic manually or via a simple script, not a fully automated canary controller)
- Jenkins-based continuous delivery (Phase 13-17, handled separately)
- multi-environment promotion (development vs. production pipelines) — that is covered in Phase 10 (Environments)
- running Terraform from GitHub Actions or introducing a remote Terraform backend; Terraform changes required to prepare IAM and the ownership boundary are still applied manually in this phase
- automatic Secret Manager version rotation; image deployment must preserve the numeric secret versions selected through Terraform

## 3. Functional requirements

1. The GitHub Actions workflow must reuse the Workload Identity Federation pool and provider managed in Phase 8, not a downloaded service account JSON key.
2. Terraform must create a dedicated deployment service account. It must not replace the existing Artifact Registry publisher or the Cloud Run runtime service account, because publishing, deployment, and application execution are separate responsibilities.
3. The deployment service account must receive only the permissions required to update the Cloud Run service, read the deployed image from the application Artifact Registry repository, and act as the existing Cloud Run runtime service account. The same repository-and-main-branch WIF restriction used by the publisher must control impersonation of the deployer.
4. The workflow must deploy to Cloud Run only after the build, test, security scan, and image push stages have all completed successfully.
5. The deployed container image must use the full Git commit SHA already published by the preceding job (e.g. `europe-west8-docker.pkg.dev/<project>/<repo>/<app>:<commit-sha>`), never the mutable `latest` alias.
6. The workflow must deploy the new revision with `--no-traffic` and a unique temporary tag derived from the commit SHA. Zero percent refers to the normal production URL; the tag supplies the dedicated URL needed to test the candidate explicitly.
7. The workflow must smoke-test the candidate URL with bounded retries. It must verify both `/actuator/health/readiness` and the read-only `/api/jobs` endpoint so that validation covers container readiness and the real database path without changing application data.
8. If either smoke-test request fails, the workflow must not run the promotion step. The previous stable revision must continue serving 100% of normal traffic, and the failed candidate must remain at 0%.
9. After a successful smoke test, the workflow must automatically promote the exact tested revision to 100% traffic. It must not promote the generic `LATEST` target, which could refer to a different revision if deployments overlap.
10. Main-branch deployments must be serialized with a GitHub Actions concurrency group so that two workflow runs cannot race while creating, testing, or promoting revisions.
11. The temporary candidate tag must be removed after the validation flow, including after a failed smoke test, so that obsolete candidate URLs do not remain publicly routable. Removing the tag must not delete the immutable revision.
12. Terraform must continue managing the Cloud Run service's structural configuration, including scaling, probes, resources, runtime identity, and numeric Secret Manager references. Its lifecycle configuration must ignore post-bootstrap changes to the container image, explicit revision name, workflow traceability labels, and traffic, which are owned by the delivery workflow. Only the known `commit-sha` and `managed-by` labels are ignored; unrelated template-label drift must remain visible.
13. The image-only deployment command must preserve the Terraform-managed Cloud Run configuration rather than replacing environment variables, secret references, probes, scaling settings, or the runtime service account.
14. Each deployment must record enough metadata to correlate the Cloud Run revision with its Git commit SHA and GitHub Actions run. The candidate revision and tag must use deterministic names derived from the commit SHA and run ID, and the workflow summary must report the full SHA, immutable image, revision, tag, and run link.
15. Pull-request workflows must still be created for documentation-only changes so that the required `Build and test` check does not remain pending. A lightweight change-classification job must allow the expensive build, dependency scan, static analysis, publish, and deployment jobs to be skipped successfully.
16. A push to `main` containing only allowlisted documentation paths must not build or publish an image and must not create a Cloud Run revision. The initial allowlist is `README.md`, `docs/**`, `specs/**`, and `LICENSE`; any changed path outside this list, including application, build, Docker, Terraform, or workflow files, must run the complete pipeline.
17. Secret scanning must still run on every pull request, including documentation-only changes, because secrets can be committed in any file type. It does not need to run again for a documentation-only push to protected `main` after the pull request has passed.

## 4. Non-functional requirements

- CI gate: the deployment stage must only run after all upstream CI stages (build, test, security scan) pass; a failure at any earlier stage must block deployment entirely.
- Security: no long-lived credentials (service account keys) must be stored as GitHub Actions secrets; Workload Identity Federation must be used to obtain short-lived tokens at runtime.
- Observability: each deployment must be traceable — given a production incident, it must be possible to identify exactly which commit SHA is currently serving traffic and which GitHub Actions run deployed it.
- Reliability: smoke-test retries must tolerate the candidate revision's cold start but remain bounded, so a genuinely broken deployment eventually fails instead of blocking indefinitely.
- State ownership: a later `terraform plan` must not propose reverting the image or traffic selected by the delivery workflow, while it must continue detecting drift in the structural settings that Terraform owns.
- Efficiency: documentation-only pull requests may create a lightweight workflow run to satisfy repository rules and run secret scanning, but must not consume the substantially larger build, Testcontainers, dependency-scan, static-analysis, Docker, Artifact Registry, or Cloud Run work.

## 5. Acceptance criteria

- [x] the existing WIF provider permits the main-branch GitHub identity to impersonate a dedicated deployer, with no service account key stored as a secret
- [x] publisher, deployer, and runtime remain distinct identities with repository/service-scoped least-privilege grants
- [x] a successful push or merge to main triggers the full pipeline (build, test, security scan, Docker build, push, deploy) end to end
- [x] the deployed image is tagged with the commit SHA, verified via `gcloud run services describe` or the Cloud Run Console
- [x] new revisions are deployed with `--no-traffic`, are tested through their temporary tagged URL, and only the exact tested revision is promoted to 100%
- [x] the smoke test verifies both the readiness endpoint and the read-only Job API database path before promotion
- [x] a deliberately failing smoke test correctly blocks traffic promotion, leaves the previous revision serving all normal traffic, and cleans up the temporary tag
- [x] rollback procedure tested manually at least once: traffic successfully redirected back to a previous stable revision using `gcloud run services update-traffic`
- [x] after an automated deployment, `terraform plan` does not attempt to restore the previous image or traffic allocation
- [x] the deployed revision retains the Terraform-managed runtime identity, secret versions, probes, resources, and scaling configuration
- [x] the full pipeline run, from push to production traffic, is visible end to end in the GitHub Actions run log
- [x] a documentation-only pull request runs secret scanning and resolves the required `Build and test` check without running build, dependency scan, static analysis, image, or deployment work
- [ ] merging that documentation-only pull request does not publish an image or create a Cloud Run revision
- [x] a mixed documentation-and-code change still executes the complete pipeline

## 6. Deliverables

- code: no application code changes expected in this phase; a small repository script may be added if it makes the smoke-test and failure-gate behavior easier to test and understand
- infrastructure: Terraform resources for the dedicated deployer, its least-privilege IAM grants and WIF impersonation binding, plus the explicit Cloud Run image/revision-metadata/traffic lifecycle ownership boundary
- workflow: keep `.github/workflows/ci.yml` as the event and dependency orchestrator, then call `.github/workflows/cloud-run-deploy.yml` after `image-publish`; the reusable workflow uses WIF authentication, deploys the immutable image without traffic, smoke-tests the tagged candidate, promotes and verifies the exact revision, and cleans up the temporary tag
- documentation: updated `docs/deployment.md` describing the full delivery pipeline, the tagging strategy, and the rollback procedure, step by step
- decisions: updated `docs/decisions.md` recording the Terraform/CD ownership boundary, the separate deployment identity, and automatic promotion after a successful smoke test

## 7. Evidence

- link to a successful GitHub Actions run showing the full pipeline from build through deployment and traffic promotion
- textual `gcloud run revisions list` and service-description output showing multiple revisions, the commit-SHA image, and the active traffic target
- GitHub Actions log of the smoke test passing before promotion
- GitHub Actions log of a controlled failing smoke test preventing promotion while the previous revision remains stable
- command output demonstrating a manual rollback to a previous revision using traffic migration
- a final empty Terraform plan demonstrating that Terraform accepts the workflow-owned image, revision metadata, and traffic while retaining management of structural configuration

## 8. Risks and mitigations

- risk: promoting a new revision to 100% traffic immediately, without any validation, could expose all users to a broken deployment at once.
  mitigation: always deploy with `--no-traffic` first and require the smoke test to pass before any traffic is shifted to the new revision.
- risk: using `latest` as an image tag would make it impossible to know exactly which code version is running at any given time, and would make Cloud Run's revision immutability guarantee less meaningful in practice.
  mitigation: always tag and deploy using the immutable commit SHA, reserving `latest` (if used at all) only as a convenience alias, never as the deployment target.
- risk: storing a service account key as a GitHub Actions secret creates a long-lived credential that, if leaked, could be used indefinitely until manually revoked.
  mitigation: use Workload Identity Federation exclusively, so GitHub Actions obtains short-lived, automatically expiring tokens tied to the specific workflow run.
- risk: without a tested rollback procedure, a bad deployment discovered after promotion could take much longer to fix than necessary.
  mitigation: document and rehearse the rollback command (`gcloud run services update-traffic --to-revisions=<previous>=100`) at least once during this phase, so it is a known, low-stress operation rather than something improvised during an incident.
- risk: Terraform and GitHub Actions could both try to restore different image, revision metadata, or traffic values on the same Cloud Run service.
  mitigation: keep structural settings in Terraform, explicitly ignore the workflow-owned image, deterministic revision name, known traceability labels, and traffic after creation, and verify the boundary with a post-deployment Terraform plan.
- risk: overlapping main-branch runs could test one revision and accidentally promote a newer untested `LATEST` revision.
  mitigation: serialize deployments and promote the deterministic revision name calculated from the service name, commit SHA, and unique GitHub Actions run ID before the candidate is created.
- risk: a tagged failed revision could remain reachable even though it receives 0% of traffic from the normal service URL.
  mitigation: use the tag only for candidate validation and remove it in a cleanup step that runs after success or failure.
- risk: an image deployment could unintentionally alter Terraform-managed secret references or runtime configuration.
  mitigation: perform an image-only update, inspect the deployed revision configuration during acceptance testing, and keep secret-version rotation as a separate explicit Terraform operation.
- risk: filtering the entire pull-request workflow by path could leave a required status check pending and block the merge.
  mitigation: always create the pull-request workflow, classify changed files in a lightweight job, and skip expensive jobs through conditions that report a completed status.
- risk: an incomplete documentation allowlist could incorrectly classify a configuration or executable change as documentation-only.
  mitigation: use a conservative allowlist in which every changed file must match a known documentation path; any unknown or mixed path triggers the full pipeline.
- risk: skipping all validation for documentation could allow a pasted credential to enter repository history.
  mitigation: keep the existing full-history Gitleaks job active for every pull request, including documentation-only changes.

## 9. Definition of done (phase)

- [x] implementation complete (dedicated deployer and WIF grant configured, deployment stage added to the pipeline, and no-traffic deploy + smoke test + exact-revision promotion flow working end to end)
- [x] tests pass (smoke test correctly gates promotion; a full pipeline run successfully deploys and promotes a new revision)
- [x] documentation updated (`docs/deployment.md` describing the delivery pipeline and the rollback procedure)
- [x] decisions recorded in `docs/decisions.md`, including WIF vs. keys, separate publisher/deployer/runtime identities, Terraform vs. delivery ownership, and automatic post-smoke-test promotion
