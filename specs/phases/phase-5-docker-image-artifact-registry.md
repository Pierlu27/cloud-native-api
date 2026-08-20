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
- Cloud SQL integration (Phase 7)
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

- [ ] Artifact Registry repository created and reachable from the pipeline
- [ ] pipeline authenticates successfully to GCP using a scoped service account
- [ ] Docker image builds successfully in CI using the existing `Dockerfile`
- [ ] image is pushed to Artifact Registry tagged with the commit SHA
- [ ] a failed build/test run does not result in an image push
- [ ] pushed image can be pulled manually from Artifact Registry and run locally to verify integrity

## 6. Deliverables

- code: no application code changes expected in this phase
- workflow: updated `.github/workflows/ci.yml` (or a new `cd.yml`) with GCP authentication, Docker build, and Artifact Registry push steps
- documentation: updated `docs/deployment.md` describing the image tagging strategy and how images are published

## 7. Evidence

- link to a CI run showing successful image build and push to Artifact Registry
- Artifact Registry console screenshot showing the pushed image with its tags
- output of pulling and running the pushed image locally
- example of a failed build run where no image was pushed

## 8. Risks and mitigations

- risk: overly broad service account permissions could allow the pipeline to perform unintended actions on the GCP project.
  mitigation: scope the service account strictly to Artifact Registry push permissions, following least privilege, and revisit scope when Cloud Run access is added in Phase 6.
- risk: relying only on `latest` could make it impossible to trace which commit produced a running image.
  mitigation: always tag with the commit SHA in addition to any semantic version tag.
- risk: credential leakage during GCP authentication in CI logs.
  mitigation: use GitHub Actions' official GCP authentication action with secret-masked output, and verify no credentials appear in plain text in the logs.

## 9. Definition of done (phase)

- [ ] implementation complete (Artifact Registry repository, pipeline authentication, build and push steps)
- [ ] tests pass (existing build/test/security gates from Phase 3-4 still green, image push only on success)
- [ ] documentation updated (`docs/deployment.md` with tagging strategy and registry details)
- [ ] decisions recorded (if needed, e.g. tagging strategy, service account scope) in `docs/decisions.md` or equivalent
