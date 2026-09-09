# Phase 16 container security and artifact publishing verification

Verification window: 2026-09-04 through 2026-09-06.

Phase 16 is complete. Jenkins security gates, controlled failures, report
publication, persistent cache, development publishing, and GitHub Actions
production delivery were verified through the real branch integration path.

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

## Development integration and publication

[PR #50](https://github.com/Pierlu27/cloud-native-api/pull/50) passed GitHub
Actions and Jenkins feature build 2 and PR-50 build 1 before merging into
`develop`. Merge commit `dbcacca800012021fbac90249f7153b9e0cc43d6` triggered
Jenkins `develop` build 4, which passed every gate, archived all four Trivy
reports, and completed Docker Push successfully.

[GitHub Actions run 34026236611](https://github.com/Pierlu27/cloud-native-api/actions/runs/34026236611)
passed all validation jobs on the same commit. Both `Build and publish image`
and `Deploy candidate and promote` were skipped, confirming development
publication belongs to Jenkins.

## Production integration and delivery

[PR #51](https://github.com/Pierlu27/cloud-native-api/pull/51) passed GitHub
Actions and Jenkins PR-51 build 1 before merging `develop` into `main`.
Merge commit `1a1c208b2902fdeb46c3ad82bb04e77aaf358494` triggered Jenkins
`main` build 3. It passed both Trivy gates, archived all four reports, and
explicitly skipped Docker Push because of its branch condition.

[GitHub Actions run 34026625556](https://github.com/Pierlu27/cloud-native-api/actions/runs/34026625556)
completed successfully, including production publication, candidate deployment,
smoke testing, promotion, serving-traffic verification, and candidate-tag
cleanup. A direct Cloud Run read confirmed:

```text
Revision: cloud-native-api-prod-sha-1a1c208b-run-34026625556
Ready:    True
Traffic:  100% to that exact revision
Tags:     no remaining candidate tag
```

The revision's resolved image digest matched the production registry digest
below. Development retained 100% traffic on
`cloud-native-api-dev-sha-6a3241b2-run-33781019836`; Phase 16 did not deploy its
newly published image.

## Final Artifact Registry evidence

Both packages exist inside repository `cloud-native-api`, region
`europe-west8`, project `project-c42baf60-7736-408b-9ff`:

| Package | Full commit-SHA tag | Additional tag | Digest |
| --- | --- | --- | --- |
| `cloud-native-api-dev` | `dbcacca800012021fbac90249f7153b9e0cc43d6` | `latest` | `sha256:964a288cd7c0eff7eefabfd950a5dbd96be91002c5c54215ea630b9953c6a963` |
| `cloud-native-api-prod` | `1a1c208b2902fdeb46c3ad82bb04e77aaf358494` | `latest` | `sha256:3db85e9283f6ceb3255bd9244acc44edfec08ad64ccc901dc5aceb1620bdb407` |

Within each package, SHA and `latest` resolved to the same digest at verification
time. Production used the immutable image resolved from its SHA tag.

## Post-push credential checks

Jenkins `develop` build 4 recorded successful authentication, both pushed
digests, the cleanup trap, Docker logout, and removal of its temporary
configuration directory. A direct agent check found no remaining
`/tmp/jenkins-docker-config.*` directory and no
`/home/jenkins/.docker/config.json`.

A non-disclosing in-memory comparison checked the real Base64 credential, a
private-key body fragment, and Docker's encoded authentication representation.
It found zero matches in tracked source files, the development build log and
archived artifacts, or Docker Agent image metadata and build history. The
image recipe accepts no publisher credential; the value is supplied at runtime
through the scoped push binding. This check records the inspected surfaces,
not a forensic scan of every image layer or every historical build.

## Result

The real development and production runs confirm complementary publisher
ownership, SHA/latest package separation, production delivery by SHA, and
post-push cleanup. Together with the clean no-push runs, independent Trivy
failure gates, retained reports, and cache-recreation test, these results close
the Phase 16 acceptance criteria. Jenkins development deployment remains
Phase 17 work.
