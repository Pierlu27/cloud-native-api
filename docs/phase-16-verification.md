# Phase 16 container security and artifact publishing verification

Verification window: 2026-09-04 onward.

Phase 16 implementation is complete on the feature branch. The local Jenkins
security gates, controlled failures, report publication, and persistent cache
have been verified. Direct `develop` and `main` publishing evidence remains
pending until the reviewed branch integrations described at the end of this
document are executed.

Evidence is recorded textually; screenshots are optional and are not required
to establish the results below.

## Reproducible Docker Agent runtime

The project-owned Docker Agent image copies Trivy `0.74.0` from its official
image and runs it as the unprivileged `jenkins` user. Compose mounts the named
volume below at Trivy's explicitly selected cache directory:

```text
cloud-native-api-jenkins-trivy-cache
    -> /home/jenkins/.cache/trivy
```

The pipeline uses the same static `docker` executor sequentially for checkout,
image build, image scan, Terraform scan, and conditional publishing. Its
workspace is independent from the Build/Test Agent, so it performs its own
`checkout scm` and derives the exact 40-character commit SHA from that checkout.

## Clean feature-branch pipeline

Jenkins feature-branch build 1 preserved the complete Phase 15 sequence on the
`build-test` agent, then allocated the Docker Agent and produced this result:

```text
Continuous Integration
  Checkout                  PASS
  Build                     PASS
  Test                      PASS
  Checkstyle                PASS
  Runtime Dependency Check  PASS
  Build Dependency Check    PASS
  Gitleaks                  PASS

Container Security & Publishing
  Checkout                  PASS
  Docker Build              PASS
  Trivy Image Scan          PASS
  Trivy IaC Scan            PASS
  Docker Push               SKIPPED - feature branch policy
```

The clean baseline contained no `HIGH` or `CRITICAL` image vulnerability and no
blocking Terraform misconfiguration. Both Trivy stages archived their JSON
source and human-readable table reports, for four retained artifacts in total.
The publisher credential was outside the feature job's execution path.

## Controlled image-vulnerability failure

Temporary branch `verify/phase-16-trivy-image-failure` downloaded Log4j Core
`2.14.1` into the image solely as a known-vulnerable fixture. Jenkins build 1
failed at Trivy Image Scan with three findings:

```text
CVE-2021-44228  CRITICAL
CVE-2021-45046  CRITICAL
CVE-2021-45105  HIGH
```

The JSON and table image reports were archived despite the non-zero gate. The
IaC scan and Docker Push never ran, so the test could not authenticate or
publish. The temporary local and remote branch and its exact local image were
deleted without merge; Jenkins retained only the diagnostic build history.

## Controlled Terraform-misconfiguration failure

A separate temporary branch, `verify/phase-16-trivy-iac-failure`, added a
disposable Terraform firewall fixture that exposed TCP port 22 to
`0.0.0.0/0`. Trivy `0.74.0` classified it through built-in rule `GCP-0027` as
`CRITICAL`.

Jenkins build 1 passed Docker Build and Trivy Image Scan, then failed at Trivy
IaC Scan with exactly that finding. Both IaC reports were archived and Docker
Push was skipped. This fixture did not reuse the project's intentional public
Cloud Run invoker policy. The temporary local and remote branch and exact local
image were deleted without merge; only Jenkins build history remains.

## Real Trivy cache persistence

After the clean scans, the named volume contained real downloaded data:

```text
Total cache data:  2.7 GB
Vulnerability DB:  1,348,702,208 bytes
Java DB:           1,517,436,928 bytes
Fanal cache:       1,048,576 bytes
```

Only the Docker Agent was force-recreated; the named volume was not removed.
The replacement container mounted the same volume, observed the same files,
sizes, and timestamps, and reconnected to the existing JCasC node. A later scan
therefore reused persisted databases instead of starting with an empty cache.

## Publisher identity and credential boundary

Terraform created `jenkins-artifact-publisher` and granted it only
`roles/artifactregistry.writer` on repository `cloud-native-api`. Terraform did
not create, read, accept, or output private key material. Its final plan
converged without unintended Cloud Run, IAM, secret, or traffic changes.

Google's inherited service-account-key creation policy was temporarily
overridden at project level only long enough to create one Jenkins key. The
override and the operator's temporary organization-policy role were then
removed, and inherited protection was verified as active again. The temporary
JSON file was deleted after its Base64 representation was placed in the ignored
local Jenkins environment.

JCasC registers only stable credential ID
`artifact-registry-publisher-key-base64`. The Jenkinsfile can bind its secret
text only inside the direct-`develop` Docker Push stage. That stage uses
`--password-stdin`, a temporary `DOCKER_CONFIG`, and unconditional logout and
directory cleanup. The tracked example contains only a placeholder.

## Environment-specific package ownership

The pipelines now implement this ownership model inside one Artifact Registry
repository:

| Execution | Built/scanned package | Allowed publication | Cloud Run delivery |
| --- | --- | --- | --- |
| Jenkins feature or pull request | `cloud-native-api-dev:<SHA>` locally | none | none |
| Jenkins direct `develop` | `cloud-native-api-dev:<SHA>` locally | dev SHA and dev `latest` | deferred to Phase 17 |
| Jenkins `main` | `cloud-native-api-dev:<SHA>` locally | none | none |
| GitHub Actions `develop` | none | none | none |
| GitHub Actions `main` | `cloud-native-api-prod:<SHA>` | prod SHA and prod `latest` | production by SHA |

Terraform maps a newly bootstrapped development Cloud Run service to the dev
package and production to the prod package. Its existing lifecycle boundary
continues to ignore subsequent pipeline-owned image, revision, label, and
traffic changes.

## Pending completion evidence

The following checks intentionally require the real integration path and must
be recorded before Phase 16 is marked complete:

1. Merge into `develop` and verify that Jenkins publishes
   `cloud-native-api-dev:<full-SHA>` plus `cloud-native-api-dev:latest`, while
   GitHub Actions runs validation but skips image publishing and Cloud Run
   delivery.
2. Merge `develop` into `main` and verify that Jenkins builds and scans but
   skips Docker Push, while GitHub Actions publishes
   `cloud-native-api-prod:<full-SHA>` plus `cloud-native-api-prod:latest` and
   deploys production from the immutable SHA.
3. List Artifact Registry packages and tags, confirming separate dev and prod
   packages and their independent `latest` aliases.
4. Inspect the successful publishing run without printing the secret and
   confirm that no key material remains in source, logs, archived reports,
   agent images, or the persistent Docker configuration.

## Current result

The implementation, clean no-push path, both independent Trivy failure gates,
unconditional report publication, identity boundary, and real cache persistence
are verified. Phase 16 remains open only for the branch-dependent publication,
production-delivery, final registry, and post-push credential-cleanup evidence.
