# Spec: Phase 17 - Jenkins Continuous Delivery for Development

## 1. Goal

Complete the Jenkins delivery path for the development environment. After the Phase 16 quality and security gates pass, Jenkins must deploy the exact development image produced by the current build as a no-traffic Cloud Run candidate, verify it through smoke tests, and promote that exact revision to 100% traffic only when it is healthy.

Production delivery remains owned by GitHub Actions. This avoids two independent systems deploying and promoting revisions on the same production Cloud Run service.

## 2. Existing baseline

Phase 16 established the following ownership model:

- Jenkins runs CI, image build, Trivy scans, and image publishing for direct builds of `develop`;
- Jenkins publishes development images to the shared Artifact Registry repository, using the development image name and both commit-SHA and `latest` tags;
- Jenkins validates `main`, feature branches, and pull requests, but it does not publish images for them;
- GitHub Actions owns production image publishing and production Cloud Run deployment from `main`, including the protected GitHub Environment approval flow;
- Terraform owns the declarative Cloud Run and IAM infrastructure, while the delivery pipeline owns revision creation and traffic promotion.

At the start of this phase, Jenkins does not deploy the development image it publishes. Therefore, the development Cloud Run service continues serving its previously deployed revision until another deployment mechanism updates it.

## 3. Scope

In scope:

- install pinned Google Cloud CLI and `jq` versions in the Jenkins Docker Agent;
- authenticate Jenkins to GCP with a dedicated development deployer service account whose credential is stored exclusively in Jenkins Credentials Management;
- create the service account and its least-privilege IAM bindings with Terraform, but create its JSON key outside Terraform so the private key never enters Terraform state;
- run delivery only for a direct `develop` branch build, after the Phase 16 build, scan, and image-push stages succeed;
- deploy the exact commit-SHA-tagged development image as a uniquely named Cloud Run candidate with `--no-traffic`;
- assign a temporary revision tag and resolve its dedicated URL;
- smoke-test the candidate readiness endpoint and one representative application endpoint before promotion;
- support a controlled smoke-test failure parameter for acceptance testing;
- promote the exact tested revision to 100% development traffic only after every smoke test succeeds;
- verify the resulting traffic assignment;
- always remove the temporary revision tag and temporary local authentication material;
- prevent overlapping Jenkins builds from promoting older development revisions after newer ones;
- record enough build metadata to associate a development revision with its commit SHA and Jenkins build.

Out of scope:

- Jenkins deployment to the production Cloud Run service;
- a Jenkins `input` approval step, approver recording, or approval timeout, because Jenkins does not own production delivery in this architecture;
- changes to the GitHub Actions production delivery pipeline or its GitHub Environment approval rule;
- gradual or canary traffic splitting;
- a dedicated OIDC identity provider for keyless local Jenkins authentication;
- application code changes;
- moving revision lifecycle ownership from the delivery pipelines back to Terraform.

A Jenkins production approval gate may be introduced in a future phase only if production delivery ownership is intentionally transferred from GitHub Actions to Jenkins.

## 4. Functional requirements

1. The Jenkins Docker Agent must contain pinned versions of the Google Cloud CLI and `jq`, so the deployment commands and JSON parsing are reproducible.
2. Terraform must create a dedicated `jenkins-cloud-run-dev-deployer` service account rather than broadening the existing Artifact Registry publisher identity.
3. The development deployer must receive only the permissions required to deploy the development Cloud Run service, read the shared Artifact Registry repository, and act as the development runtime service account. Its permissions must not allow deployment to production.
4. Terraform must not create or store the service account JSON key. The key must be generated outside Terraform, encoded as Base64, and stored as a Jenkins secret-text credential with a stable ID such as `cloud-run-dev-deployer-key-base64`.
5. The real credential value must enter the local Jenkins stack only through the ignored Jenkins environment file. Tracked example files must contain the variable name and explanatory placeholder only.
6. Delivery stages must run only when `BRANCH_NAME == 'develop'` and `CHANGE_ID` is absent. Feature branches, pull requests, and `main` must never bind the deployment credential or execute Jenkins deployment commands.
7. Jenkins must authenticate in an isolated temporary `CLOUDSDK_CONFIG`, decode the private key only into a temporary file, activate the service account without printing the key, and remove both the decoded key and temporary Cloud CLI configuration in cleanup.
8. The pipeline must derive and validate the full Git commit SHA from the checked-out source and deploy the development image tagged with that exact SHA. It must not deploy an unqualified or floating `latest` tag.
9. Each deployment must use a unique, Cloud Run-compatible revision name and candidate tag derived from the commit SHA plus Jenkins build identity, avoiding collisions when the same commit is rebuilt.
10. The `Deploy Candidate` stage must update only the development Cloud Run service and use `--no-traffic`, leaving the previously stable revision at 100% while validation is in progress.
11. Jenkins must resolve the tagged candidate revision URL from Cloud Run after deployment rather than construct the URL by assumption.
12. The `Smoke Test` stage must call the candidate's Actuator readiness endpoint and a representative application endpoint, such as `/api/jobs`, with explicit connection timeout, total timeout, and bounded retries for transient startup delay.
13. A boolean test parameter must be able to force failure only after the real smoke requests have run. This provides a deterministic negative-path test without weakening normal validation.
14. If authentication, candidate deployment, URL resolution, or either smoke test fails, the pipeline must stop before traffic promotion. The previously stable development revision must remain at 100% traffic.
15. The `Traffic Promotion` stage must promote the exact revision that passed smoke testing to 100% development traffic; it must not implicitly promote whichever revision happens to be latest.
16. After promotion, Jenkins must query Cloud Run and verify that the tested revision owns 100% of development traffic. A failed verification must fail the build.
17. Candidate-tag cleanup and temporary authentication cleanup must run even when an earlier delivery stage fails. Removing a tag must not delete the revision or alter stable traffic.
18. The pipeline must prevent concurrent delivery builds from creating out-of-order promotions, for example by using `disableConcurrentBuilds()` for the Multibranch job.
19. Jenkins build output or build metadata must expose the target environment, full commit SHA, deployed revision name, and Jenkins build number without exposing credentials.

## 5. Non-functional requirements

- CI and security gate: delivery must be structurally unreachable unless the Phase 16 build, test, Trivy image scan, Trivy IaC scan, and development image push all succeed.
- Security: the deployment credential is a long-lived local-development compromise. It must be least-privileged, masked by Jenkins, limited to the development environment, rotated periodically, and never printed or archived.
- Ownership: Jenkins must not change the production Cloud Run service, while GitHub Actions must remain the only production delivery owner.
- Traceability: a development revision must be traceable to the exact Git commit and Jenkins build that created and promoted it.
- Repeatability: tool versions, deployed image tag, revision name, target project, region, repository, and service must be explicit rather than inferred from mutable defaults.
- Cost control: the phase must reuse the existing development Cloud Run service and Artifact Registry repository and must not introduce an additional always-on workload.

## 6. Acceptance criteria

- [x] the Jenkins Docker Agent exposes the pinned Google Cloud CLI and `jq` versions
- [x] Terraform creates the dedicated development deployer and its least-privilege bindings without storing a private key in Terraform state
- [x] Jenkins authenticates successfully using the dedicated Base64 service-account credential from Jenkins Credentials Management
- [x] feature branch, pull request, and `main` builds skip every Jenkins delivery stage and never bind the development deployer credential
- [x] a successful direct `develop` build automatically deploys to the development Cloud Run service without a manual approval step
- [x] the deployed candidate uses the exact commit-SHA image produced by that build and initially receives 0% traffic
- [x] the smoke-test stage verifies both candidate readiness and the representative application endpoint through the candidate URL
- [x] a deliberately forced smoke failure blocks promotion, leaves the previously stable revision at 100%, and still performs cleanup
- [x] a successful smoke test promotes the exact tested revision to 100% development traffic
- [x] post-promotion verification confirms the expected revision and traffic assignment
- [x] temporary candidate tags, decoded key material, and temporary Cloud CLI configuration are removed on both success and failure paths
- [x] Jenkins build history identifies the development environment, commit SHA, revision, and build number
- [x] a final Terraform plan reports no unexpected infrastructure drift after the resources have been applied

## 7. Deliverables

- `Jenkinsfile`: development-only authentication, candidate deployment, smoke testing, forced-failure verification, exact revision promotion, traffic verification, concurrency protection, and unconditional cleanup;
- `jenkins/docker-agent/Dockerfile`: pinned Google Cloud CLI and `jq` tooling;
- `jenkins/docker-compose.yml`, `jenkins/controller/jenkins.yaml`, and `jenkins/agent-secrets.env.example`: secret injection and stable Jenkins credential registration without a real secret in Git;
- Terraform IAM resources for the separate Jenkins development deployer, repository read access, service-scoped Cloud Run deployment access, and development runtime service-account impersonation;
- `docs/jenkins.md` and `docs/deployment.md`: updated ownership model, delivery flow, credential setup and rotation, cleanup behavior, and recovery guidance;
- `docs/decisions.md`: ADR covering split delivery ownership, key-based Jenkins authentication, least privilege, exact-revision promotion, and the decision to defer Jenkins production approval;
- `docs/phase-17-verification.md`: reproducible clean-run and controlled-failure evidence;
- repository README links and summary updated where necessary.

## 8. Evidence

- Jenkins direct-`develop` run showing the Phase 16 gates followed by authentication, candidate deployment, smoke tests, exact revision promotion, verification, and cleanup;
- Cloud Run revision and traffic output showing the candidate at 0% before promotion and the same revision at 100% after promotion;
- Jenkins controlled-failure run showing real smoke requests followed by forced failure, skipped promotion, unchanged stable traffic, and completed cleanup;
- Jenkins feature/PR/`main` run evidence showing that development delivery and credential binding were skipped;
- agent tool-version output for Google Cloud CLI and `jq`;
- Terraform validation, plan/apply, and final no-op plan output;
- Artifact Registry and Cloud Run identifiers that correlate the deployed SHA image, revision, and Jenkins build without exposing secret material.

## 9. Risks and mitigations

- risk: a GCP service account key is a long-lived credential and is more exposed than the short-lived Workload Identity Federation token used by GitHub Actions.
  mitigation: restrict the identity to development-only permissions, store the Base64 value only in Jenkins Credentials Management, isolate authentication state, delete temporary material after every run, rotate the key, and document keyless Jenkins authentication as a future improvement.
- risk: giving the existing Artifact Registry publisher additional Cloud Run permissions would combine image publication and deployment authority in one identity.
  mitigation: create a separate development deployer identity with an independent credential and narrowly scoped bindings.
- risk: concurrent `develop` builds could finish out of order and cause an older revision to replace a newer one.
  mitigation: disable concurrent builds or otherwise serialize the delivery path, and promote only the revision recorded by the current build.
- risk: candidate URL startup may be briefly unavailable while a scale-from-zero instance initializes.
  mitigation: use bounded retries and explicit timeouts; never route stable traffic merely to make the smoke test easier.
- risk: a scripting error could promote an untested revision.
  mitigation: persist the resolved candidate revision identifier within the build and use that exact identifier for smoke-test traceability, promotion, and verification.
- risk: two delivery systems could race on production if Jenkins later gains production deployment commands without removing GitHub Actions ownership.
  mitigation: explicitly exclude Jenkins production delivery from this phase and require a separate architectural decision before changing ownership.

## 10. Definition of done (phase)

- [x] implementation complete for the Jenkins development delivery path
- [x] clean direct-`develop` delivery verified end to end
- [x] controlled smoke-test failure verified without development traffic impact
- [x] feature branch, pull request, and `main` delivery exclusion verified
- [x] temporary authentication and candidate-tag cleanup verified on success and failure
- [x] Terraform IAM changes validated, applied, and followed by a no-op plan
- [x] documentation and ADR updated with the final implementation and credential-rotation procedure
- [x] Phase 17 verification document records reproducible textual evidence without committing secrets
