# Deployment Guide

## Prerequisites

- GCP project
- account with the minimum required roles
- gcloud CLI
- Terraform
- GitHub repository with configured secrets

## Artifact Registry publishing

The project publishes images to the Docker repository
`europe-west8-docker.pkg.dev/project-c42baf60-7736-408b-9ff/cloud-native-api`.
The `image-publish` GitHub Actions job runs only for pushes to `main` and only
after the build, test, dependency, secret, and static-analysis jobs succeed.

Authentication uses Workload Identity Federation, not a long-lived JSON key.
The repository requires these GitHub Actions secrets:

- `WIF_PROVIDER`
- `WIF_SERVICE_ACCOUNT`

The service account has only `roles/artifactregistry.writer` on the
`cloud-native-api` repository.

Each published image receives the immutable commit tag `${GITHUB_SHA}` and the
`latest` convenience alias. The SHA tag is the traceability source of truth;
`latest` is never the only identifier. The workflow prints the pushed manifest
digest so it can be matched to the commit.

Pull an image locally with:

```bash
gcloud auth configure-docker europe-west8-docker.pkg.dev
docker pull europe-west8-docker.pkg.dev/project-c42baf60-7736-408b-9ff/cloud-native-api/cloud-native-api:<commit-sha>
docker run --rm -p 8080:8080 europe-west8-docker.pkg.dev/project-c42baf60-7736-408b-9ff/cloud-native-api/cloud-native-api:<commit-sha>
```

### Phase 5 verification (2026-08-20)

The `main` image was published with commit tag
`a036cb9425a4d4fff1191cfdb37a523164c79706` and manifest digest
`sha256:75059f78ee5e29f92b3821fc76ccb9fec2f18cb4bd8e84971f2902a7521567b7`.
The exact SHA-tagged image was pulled successfully from Artifact Registry.
It starts the Spring Boot/Tomcat process locally; a complete application health
check requires the configured PostgreSQL datasource variables (the standalone
container exits when `SPRING_DATASOURCE_URL` is not provided).

## Target flow

1. Infrastructure provisioning with Terraform
2. Build + test + scan in CI
3. Build/push image to Artifact Registry
4. Deploy to Cloud Run
5. Verify health endpoint and logs

## Rollback (to complete in Phase 10)

- use the previous Cloud Run revision
- keep versioned image tags (not only `latest`)
