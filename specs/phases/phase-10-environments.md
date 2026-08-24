# Spec: Phase 10 - Environments

## 1. Goal

Separate development and production so that changes can be validated in an isolated environment before reaching the environment real traffic depends on, without doubling infrastructure costs.

## 2. Scope

In scope:

- two logical environments: `development` and `production`
- separate Cloud Run services named `cloud-native-api-dev` and `cloud-native-api-prod` within the same GCP project, to avoid the cost of maintaining fully separate projects
- staged migration from the existing `cloud-native-api` service: keep it available as a rollback fallback until the new production service is verified, then retire it explicitly rather than attempting an in-place rename
- two separate Supabase Free Plan projects for development and production data isolation: adopt the project already used by the application as production and create a second project dedicated to development
- branch-based deployment mapping: `develop` branch deploys to the development environment, `main` branch deploys to production
- GitHub Actions Environments configured with protection rules (e.g. required approval before deploying to production)
- environment-specific configuration kept separate and never shared between environments: non-sensitive deployment metadata belongs to the corresponding GitHub Environment, while database payloads remain exclusively in environment-specific Google Secret Manager secrets

Out of scope:

- separate GCP projects per environment (deliberately avoided in this phase to control cost and complexity; documented as a possible future improvement)
- a full staging/QA environment as a third stage (only development and production are required per the project roadmap)
- Jenkins-based environment promotion (Phase 13-17, handled separately if applicable)
- copying database passwords or connection strings into GitHub Environment secrets; Phase 8 established Google Secret Manager as the sole runtime secret store
- schema-only isolation inside one Supabase project; the selected design uses two dedicated Postgres instances instead

## 3. Functional requirements

1. Two Cloud Run services must exist: `cloud-native-api-dev` for development and `cloud-native-api-prod` for production, each with its own service URL and configuration. The historical `cloud-native-api` service may coexist only during the verified migration window and is not part of the final two-environment topology.
2. Two separate Supabase projects must exist. The current application project becomes the production target and a newly created Free Plan project becomes the development target, so development work never touches the production Postgres instance.
3. The GitHub Actions pipeline must deploy to the development Cloud Run service automatically when changes are pushed or merged to the `develop` branch.
4. The GitHub Actions pipeline must deploy to the production Cloud Run service only when changes are merged to the `main` branch.
5. GitHub Environments must be configured in the repository settings for both `development` and `production`, with `production` requiring at least one manual approval before the deployment job runs.
6. Each environment must have distinct Google Secret Manager containers for its Supabase URL, username, and password. Secret payloads must not enter Terraform state or GitHub secrets. GitHub Environments may contain only non-sensitive deployment variables such as the Cloud Run service name and the deployer service-account email.
7. It must be possible to determine, from the Cloud Run service name and its currently serving revision, which environment and which commit are running at any given time.
8. Development and production must use separate Cloud Run runtime service accounts. Each runtime identity may read only its own environment's database secrets.
9. WIF must trust both `develop` and `main` without making them equivalent: the `develop` identity may impersonate only the development deployer, while the `main` identity may impersonate only the production deployer. No long-lived Google service-account key may be stored in GitHub.
10. URL, username, and password secret versions must be pinned independently for each environment, so rotating one value does not require creating duplicate versions for unchanged values. Image delivery must not advance these numeric references implicitly.

## 4. Non-functional requirements

- CI gate: the existing build/test/security/deploy pipeline from Phase 3-9 must run identically for both environments; only the deployment target and its approval requirements differ.
- Security: production database secrets must not be readable by the development runtime identity, and workflow runs from `develop` must not be able to impersonate the production deployer. Secret Manager IAM, branch-scoped WIF impersonation, and GitHub Environment protection rules must enforce these complementary boundaries.
- Observability: Cloud Run service names and Supabase project names must be labeled or named clearly enough (e.g. `-dev` / `-prod` suffixes) that it is never ambiguous which environment is being inspected in the GCP Console or Supabase dashboard.

## 5. Acceptance criteria

- [ ] two Cloud Run services exist and are independently deployable (`cloud-native-api-dev`, `cloud-native-api-prod`), and the historical unsuffixed service is retired only after production verification
- [ ] pushing to `develop` triggers an automatic deployment to the development Cloud Run service, with no manual approval required
- [ ] merging to `main` triggers a deployment to the production Cloud Run service that pauses for manual approval before running
- [ ] development and production point to two distinct Supabase projects, verified by writing a test record in development and confirming it does not appear in production
- [ ] environment secrets and deployment identities are scoped correctly: development cannot read production Secret Manager payloads or impersonate the production deployer
- [ ] both Cloud Run services and both Supabase projects are clearly named/labeled to avoid confusion between environments
- [ ] each environment can advance one database secret version without changing the other two numeric references

## 6. Deliverables

- code: no application code changes expected in this phase, aside from any environment-driven configuration keys already anticipated in earlier phases
- workflow: updated GitHub Actions workflow(s) with branch-based deployment targets and `environment:` keys referencing the configured GitHub Environments
- documentation: updated `docs/deployment.md` describing the two environments, their branch mapping, approval rules, Secret Manager and identity boundaries, independent secret rotation, shared observability, staged migration, and how to tell the environments apart at a glance
- decisions: updated `docs/decisions.md` recording the explicit `-dev`/`-prod` service names, the single-GCP-project tradeoff, the two-Supabase-project isolation model, and why database payloads remain exclusively in Secret Manager rather than being duplicated in GitHub

## 7. Evidence

Textual, sanitized command output and direct GitHub Actions run links are the
default evidence for this phase. Screenshots are optional and are not required
for acceptance. The Phase 3 screenshots remain as historical UI evidence, not
as a rule for later phases.

- sanitized GitHub repository Environment configuration showing `development` and `production`, their branch policies, and production's required reviewer rule
- link to a GitHub Actions run showing an automatic deployment to development from a `develop` branch push
- link to a GitHub Actions run showing a production deployment paused on a manual approval step, then completed after approval
- sanitized `gcloud run services list` or Terraform output showing both Cloud Run services with distinct names
- textual API verification confirming that a uniquely identifiable record written in development does not appear in production
- sanitized Terraform, Secret Manager IAM, and WIF output showing that development and production runtime/deployer identities cannot cross their environment boundary
- final reviewed Terraform plan showing the intended legacy-resource retirement, followed by a no-op plan after removal

## 8. Risks and mitigations

- risk: keeping both environments in the same GCP project reduces cost but also reduces isolation; a misconfigured IAM policy or Terraform change could accidentally affect both environments at once.
  mitigation: use clearly distinct resource names and separate runtime/deployer service accounts per environment, and treat any Terraform change affecting both environments in a single apply as a signal to review the change more carefully before applying.
- risk: reusing a Secret Manager container, runtime identity, or deployer across environments could let development read production data or update the production service.
  mitigation: create environment-suffixed secret containers and runtime/deployer service accounts, grant secret access per resource, restrict WIF impersonation by branch, and verify the negative cross-environment cases explicitly.
- risk: without a required approval step, a merge to `main` could deploy directly to production without any human review, defeating the purpose of separating environments in the first place.
  mitigation: configure the `production` GitHub Environment with at least one required reviewer, and verify it blocks the deployment job until approved.
- risk: using two separate Supabase Free tier projects doubles the exposure to Free tier limitations (storage, egress, auto-pause) documented in Phase 7.
  mitigation: keep both projects within the provider's current Free Plan limits, recheck those limits when the environment is recreated, treat development as disposable, and accept that either low-activity project may require manual resume after Supabase auto-pauses it.
- risk: replacing the historical production service changes its public URL and an immediate cutover would remove the known rollback target.
  mitigation: create and validate `cloud-native-api-prod` alongside `cloud-native-api`, switch consumers only after end-to-end verification, retain the historical service during an explicit rollback window, and retire it as a separate reviewed operation.
- risk: one shared secret-version number for URL, username, and password would couple otherwise independent rotations and could make Cloud Run reference versions that do not exist.
  mitigation: keep three numeric version entries per environment, change only the affected entry, review the resulting revision plan, and leave the previous version enabled through the rollback window.
- risk: deleting the historical Terraform blocks could also discard useful explanations or accidentally include shared infrastructure in the retirement change.
  mitigation: classify legacy and shared resources first, consolidate still-valid comments into the environment-aware `for_each` resources, remove obsolete or duplicate comments, and review the complete deletion plan before applying it. Historical secrets are evaluated separately and are never implied deletions.

## 9. Definition of done (phase)

- [ ] implementation complete (two Cloud Run services, two Supabase projects, environment-specific runtime/deployer identities and secrets, branch-based deployment mapping, GitHub Environment protection rules, independent secret-version references, consolidated Terraform comments, and verified retirement of the historical service)
- [ ] tests pass (deployments to both environments verified working end to end, with production correctly gated behind approval)
- [x] documentation updated (`docs/deployment.md` describing the environment separation strategy and branch mapping)
- [x] decisions recorded (single GCP project, two Supabase projects, explicit environment suffixes, and Secret Manager as the sole database secret store) in `docs/decisions.md` or equivalent

## 10. Current implementation status

Implemented and locally validated:

- environment-aware Terraform resources for the two Cloud Run services, six Secret Manager containers, separate runtime/deployer identities, scoped IAM, and branch/environment WIF bindings
- two Supabase projects and their environment-specific secret payloads, added outside Terraform
- `develop`/`main` workflow routing, GitHub Environment variables, development branch policy, and the production reviewer gate
- independently pinned URL, username, and password versions for both environments
- shared 5xx observability covering the historical, development, and production service names
- Terraform formatting and validation, followed by a no-op plan against the applied infrastructure

Still requiring end-to-end evidence:

- pull-request CI and automatic deployment after merging the feature branch into `develop`
- development smoke tests and proof of data isolation from production
- pull-request CI, production approval pause, deployment, and smoke tests after promotion to `main`
- consumer cutover, rollback-window completion, comment consolidation, and reviewed retirement of the historical service and its legacy IAM/identities
