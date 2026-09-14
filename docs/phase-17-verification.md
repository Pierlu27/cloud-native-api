# Phase 17 Jenkins development delivery verification

Verification window: 2026-09-13 through 2026-09-14.

Phase 17 adds development-only Cloud Run delivery to the Jenkins pipeline.
Evidence is recorded textually; screenshots are optional and are not required
to establish the results below.

## Delivery ownership and branch boundary

The final ownership model remains intentionally split:

| Pipeline context | Development image push | Development deploy | Production deploy |
|---|---:|---:|---:|
| Jenkins internal feature branch | no | no | no |
| Jenkins same-repository pull request | no | no | no |
| Jenkins direct `develop` | yes | yes | no |
| Jenkins direct `main` | no | no | no |
| GitHub Actions direct `main` | no | no | yes |

Every Jenkins delivery stage evaluates the same direct-build predicate:
`BRANCH_NAME == 'develop'` and no `CHANGE_ID`. The deployment credential is
bound only after that predicate passes. Feature build 2 and the PR-55 build
executed all CI, Docker, and Trivy gates while skipping image publication and
every delivery stage. The `main` exclusion follows the same evaluated
predicate and remains to be observed once this phase reaches `main` through the
normal integration path.

PR [#55](https://github.com/Pierlu27/cloud-native-api/pull/55) merged the Phase
17 implementation into `develop` as commit
`0e64f8b711c0dee53374ebba4eb33ae0368e7cc0`.

## Reproducible delivery tooling

The project-owned Docker Agent contains Google Cloud CLI `584.0.0` and `jq`
`1.8.2`. The root Jenkinsfile uses their explicit project, repository, region,
service, and image inputs rather than relying on mutable Cloud CLI defaults.

The successful and controlled-failure runs both selected this immutable package
and tag:

```text
Package: europe-west8-docker.pkg.dev/project-c42baf60-7736-408b-9ff/cloud-native-api/cloud-native-api-dev
Tag:     0e64f8b711c0dee53374ebba4eb33ae0368e7cc0
```

Rebuilding the same commit reused that SHA image identity but produced a unique
Cloud Run revision and candidate tag through the Jenkins build number.

## Development deployer and authentication cleanup

Terraform creates dedicated service account
`jenkins-cloud-run-dev-deployer`. Its permissions are limited to:

- reading the shared Artifact Registry repository;
- updating only `cloud-native-api-dev`; and
- acting as only the development runtime service account.

Terraform does not create, read, or store its private key. The manually created
key is represented in Jenkins by credential ID
`cloud-run-dev-deployer-key-base64` and enters the Docker Agent only inside the
development authentication stage.

Each delivery run creates a unique `/tmp/jenkins-gcloud-config.*` directory,
decodes the JSON key into that temporary boundary without printing it,
activates the expected account, and deletes the decoded file immediately. The
always-run cleanup revokes Cloud CLI authentication and removes the complete
temporary directory. Direct post-run checks after builds 7 and 8 found zero
matching directories. A manual `gcloud` call after cleanup correctly had no
active account, confirming that authentication did not persist in the agent.

## First integration attempt and external dependency diagnosis

The webhook-triggered direct-`develop` build 6 reached the new delivery path
and created candidate revision:

```text
cloud-native-api-dev-sha-0e64f8b7-build-6
```

Cloud Run could not make the candidate ready because the development Supabase
project was paused. Application startup reported the database host error
`ENOTFOUND`, and the stable development URL also returned HTTP 503. This
confirmed a shared external-database outage rather than an image or delivery
script defect.

The failure was safe: promotion never ran, the previously stable revision kept
100% traffic, the candidate tag was removed, and temporary authentication was
deleted. After the Supabase project resumed, both the stable readiness endpoint
and `/api/jobs` returned successful responses.

## Successful direct-development delivery

Jenkins `develop` build 7 reran the same merge commit with
`FORCE_SMOKE_TEST_FAILURE=false`. The complete Phase 15 and Phase 16 gates ran
before delivery. Jenkins then recorded:

```text
Environment: development
Commit:      0e64f8b711c0dee53374ebba4eb33ae0368e7cc0
Revision:    cloud-native-api-dev-sha-0e64f8b7-build-7
Candidate:   cand-0e64f8b7-b7
```

The run produced this sequence:

```text
candidate deployed with 0% normal service traffic
  -> tagged candidate URL resolved from Cloud Run
  -> /actuator/health/readiness passed
  -> /api/jobs passed
  -> exact build-7 revision promoted to 100%
  -> exact build-7 traffic verified at 100%
  -> temporary tag and gcloud configuration removed
  -> Jenkins result SUCCESS
```

The run took approximately 4 minutes 54 seconds. Cloud Run reported both its
latest created and latest ready revision as build 7, with normal service
traffic assigned to that exact revision.

## Controlled smoke-test failure

Jenkins `develop` build 8 used the same immutable commit image and
`FORCE_SMOKE_TEST_FAILURE=true`. It created distinct candidate revision and tag:

```text
Revision:  cloud-native-api-dev-sha-0e64f8b7-build-8
Candidate: cand-0e64f8b7-b8
```

Both real smoke requests passed before the deterministic failure was raised.
Jenkins then stopped before `Traffic Promotion`, returned the expected
`FAILURE`, removed the candidate tag, revoked authentication, and deleted the
temporary Cloud CLI directory.

Cloud Run state inspected during cleanup repeatedly showed:

```text
cloud-native-api-dev-sha-0e64f8b7-build-7  -> 100% normal traffic
cloud-native-api-dev-sha-0e64f8b7-build-8  -> candidate tag only, no percentage
```

This proves that a failed candidate cannot replace the previously verified
revision merely because it is newer.

## Latest-ready versus serving revision

Build 8 passed Cloud Run startup and both real application checks before the
artificial pipeline failure. Cloud Run therefore classifies it as the newest
`Ready` revision even though Jenkins did not promote it:

```text
latestReadyRevisionName  = build-8
100% serving revision    = build-7
```

`latestReadyRevisionName` is creation/readiness metadata, not a traffic
decision. Operators must inspect `status.traffic` when identifying the live
revision. The pipeline likewise promotes and verifies an explicit revision
name rather than using `LATEST`.

## Terraform convergence

The first final Terraform plan detected only that the computed
`environment_cloud_run_latest_ready_revisions.development` output was stale.
A reviewed `terraform plan -refresh-only` recorded the pipeline-owned Artifact
Registry, IAM metadata, Cloud Run revision, and traffic observations without
changing remote objects. Applying that plan reported:

```text
Resources: 0 added, 0 changed, 0 destroyed
```

The temporary binary plan was deleted. A subsequent normal `terraform plan`
reported:

```text
No changes. Your infrastructure matches the configuration.
```

This confirms the intended ownership boundary: Terraform retains stable
infrastructure and IAM ownership, while Jenkins creates development revisions
and promotes traffic without causing corrective infrastructure drift.

## Result

The direct-development success path, deterministic non-promotion path,
external-dependency failure path, exact-revision traffic checks, and
unconditional credential/tag cleanup all behaved as designed. The only
remaining integration observation is the expected Jenkins `main` delivery skip
after the completed phase reaches `main`.
