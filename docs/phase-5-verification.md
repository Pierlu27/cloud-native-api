# Phase 5 Artifact Registry Verification

Verification date: 2026-08-20.

Phase 5 added the first delivery artifact after the CI and security gates: an
immutable application container image published to Google Artifact Registry.
The phase did not deploy that image to Cloud Run and did not yet manage the GCP
resources with Terraform.

## Repository and publishing identity

- GCP project: `project-c42baf60-7736-408b-9ff`
- region: `europe-west8`
- Artifact Registry repository: `cloud-native-api`
- image name: `cloud-native-api`
- publisher service account: `github-artifact-publisher`
- publisher permission: `roles/artifactregistry.writer`, scoped to the single
  application repository

GitHub Actions authenticates without a downloaded JSON key. The workflow obtains
a short-lived GitHub OIDC token, passes it through the `github-actions` Workload
Identity Federation pool/provider, and impersonates the publisher service
account. The publisher identity builds or runs no application workload; it can
only upload artifacts to the repository.

## Successful workflow evidence

[GitHub Actions run 32372224961](https://github.com/Pierlu27/cloud-native-api/actions/runs/32372224961)
completed successfully for commit:

```text
a036cb9425a4d4fff1191cfdb37a523164c79706
```

Its
[Build and publish image job](https://github.com/Pierlu27/cloud-native-api/actions/runs/32372224961/job/96435766037)
authenticated to GCP, built the repository `Dockerfile`, pushed the image, and
reported this manifest digest:

```text
sha256:75059f78ee5e29f92b3821fc76ccb9fec2f18cb4bd8e84971f2902a7521567b7
```

The workflow assigns two tags to the same build:

- the complete Git commit SHA, which is immutable and provides traceability;
- `latest`, which is only a moving convenience alias and is never the sole
  deployment identifier.

The exact SHA-tagged image was pulled successfully from Artifact Registry and
started locally. A standalone container requires the datasource environment
variables to complete application startup; absence of those runtime variables
does not indicate a damaged image.

## CI gate behavior

The `image-publish` job:

- runs only for a `push` to `main`, not for a pull request;
- declares build/test, runtime dependency, build dependency, secret scan, and
  static analysis jobs in `needs`;
- cannot start if one of those required jobs fails;
- prints the pushed image digest so the registry artifact can be matched to its
  source commit.

Phase 6 subsequently deployed an immutable image from this repository to Cloud
Run, providing an additional integrity check beyond the local pull.

## Evolution in Phase 8

Phase 8 imported the repository, publisher service account, WIF pool/provider,
impersonation member, and repository writer member into Terraform. A final
no-op plan confirmed that adoption did not change the publishing relationship.
The workflow continues to publish images; Terraform declares infrastructure and
does not trigger a workflow run.
