# Spec: Phase 5 - Docker Image & Artifact Registry

## 1. Goal

Automatically publish the Docker image built from the application into a cloud container registry (GCP Artifact Registry) as part of the GitHub Actions pipeline, with proper authentication, tagging, and versioning.

## 2. Scope

In scope:

- creation of a GCP Artifact Registry repository
- pipeline authentication to GCP (service account or workload identity federation)
- Docker image build step in the GitHub Actions pipeline
- image push to Artifact Registry
- image tagging strategy (version tag and/or commit SHA, avoiding sole reliance on `latest`)

Out of scope:

- deployment of the image to Cloud Run (Phase 6)
- managed PostgreSQL integration (Phase 7, implemented with Supabase instead of Cloud SQL)
- Terraform-managed provisioning of Artifact Registry (Phase 8 formalizes this as IaC; this phase can use manual/CLI setup)
- Jenkins-side image build and push (Phase 14-18, handled separately)

## 3. Functional requirements

1. An Artifact Registry repository must exist on GCP to host the application's Docker images.
2. The GitHub Actions pipeline must authenticate to GCP using a dedicated service account with least-privilege permissions scoped to Artifact Registry push access.
3. The pipeline must build the Docker image using the `Dockerfile` from Phase 2 after the build/test stage succeeds.
4. The pipeline must tag the image with at least the Git commit SHA; a semantic version tag may be added for tagged releases.
5. The pipeline must push the tagged image to the Artifact Registry repository.
6. The pipeline must not push an image if the build or test stage failed earlier in the same run.
7. The image push step must not rely solely on the `latest` tag as the only identifier of a build.

## 4. Non-functional requirements

- CI gate: image build and push must only execute after unit tests, integration tests, and the Phase 4 security/quality checks have passed.
- Security: GCP service account credentials used by the pipeline must be stored as GitHub Actions secrets, never committed to the repository; the service account must be scoped only to the permissions required for pushing images.
- Observability: the pipeline must output the final image tag/digest pushed, so it can be traced back to the exact commit that produced it.

## 5. Acceptance criteria

- [x] Artifact Registry repository created and reachable from the pipeline
- [x] pipeline authenticates successfully to GCP using a scoped service account
- [x] Docker image builds successfully in CI using the existing `Dockerfile`
- [x] image is pushed to Artifact Registry tagged with the commit SHA
- [x] a failed build/test run does not result in an image push
- [x] pushed image can be pulled manually from Artifact Registry and run locally to verify integrity

## 6. Deliverables

- code: no application code changes expected in this phase
- workflow: updated `.github/workflows/ci.yml` (or a new `cd.yml`) with GCP authentication, Docker build, and Artifact Registry push steps
- documentation: updated `docs/deployment.md` describing the image tagging strategy and how images are published

## 7. Evidence

Detailed verification: [`docs/phase-5-verification.md`](../../docs/phase-5-verification.md).

Completion record (2026-08-20):

- [GitHub Actions run 32372224961](https://github.com/Pierlu27/cloud-native-api/actions/runs/32372224961)
  completed successfully for commit
  `a036cb9425a4d4fff1191cfdb37a523164c79706`;
- its
  [Build and publish image job](https://github.com/Pierlu27/cloud-native-api/actions/runs/32372224961/job/96435766037)
  authenticated to Google Cloud through Workload Identity Federation, built
  the Docker image, pushed both the immutable commit SHA tag and the `latest`
  convenience tag, and reported the resulting manifest digest;
- the publish job declares all build, test, dependency, secret, and static
  analysis jobs in `needs`, so GitHub Actions cannot start it when an upstream
  gate fails. It also runs only for pushes to `main`, not for pull requests;
- `docs/deployment.md` records the published SHA tag and digest and confirms
  that the exact SHA-tagged image was pulled successfully from Artifact
  Registry and started locally;
- the same Artifact Registry image was subsequently deployed successfully to
  Cloud Run in Phase 6, providing an additional integrity check.

## 8. Risks and mitigations

- risk: overly broad service account permissions could allow the pipeline to perform unintended actions on the GCP project.
  mitigation: scope the service account strictly to Artifact Registry push permissions, following least privilege, and revisit scope when Cloud Run access is added in Phase 6.
- risk: relying only on `latest` could make it impossible to trace which commit produced a running image.
  mitigation: always tag with the commit SHA in addition to any semantic version tag.
- risk: credential leakage during GCP authentication in CI logs.
  mitigation: use GitHub Actions' official GCP authentication action with secret-masked output, and verify no credentials appear in plain text in the logs.

## 9. Definition of done (phase)

- [x] implementation complete (Artifact Registry repository, pipeline authentication, build and push steps)
- [x] tests pass (existing build/test/security gates from Phase 3-4 still green, image push only on success)
- [x] documentation updated (`docs/deployment.md` with tagging strategy and registry details)
- [x] decisions recorded (if needed, e.g. tagging strategy, service account scope) in `docs/decisions.md` or equivalent
