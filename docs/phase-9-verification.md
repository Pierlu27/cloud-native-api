# Phase 9 Continuous Delivery Verification

Verification date: 2026-08-23.

This document records the reproducible evidence for the GitHub Actions delivery
flow introduced in Phase 9. It uses workflow links, sanitized CLI output, and
HTTP results instead of mandatory Console screenshots.

## Successful end-to-end delivery

[GitHub Actions run 32653385587](https://github.com/Pierlu27/cloud-native-api/actions/runs/32653385587)
completed successfully for main commit:

```text
e4d5c1c9edd46d20a68e61ad4e058e6707a34b7e
```

The run completed the change classifier, secret scan, application dependency
scan, build dependency scan, static analysis, build and tests, image publish,
candidate deployment, smoke test, exact-revision promotion, traffic
verification, and candidate-tag cleanup. The deployment job created:

```text
image tag: e4d5c1c9edd46d20a68e61ad4e058e6707a34b7e
revision:  cloud-native-api-sha-e4d5c1c9-run-32653385587
tag:       candidate-e4d5c1c9-32653385587
traffic:   100% after validation
```

The candidate was initially deployed without normal service traffic. Its
temporary tagged URL was used to call both
`/actuator/health/readiness` and the read-only `/api/jobs` database path. Only
the exact revision named above was then promoted; the workflow did not use the
moving `LATEST` target. The temporary tag was removed after validation.

The same merge changed both documentation and `terraform/cloud-run.tf`. The
classifier therefore treated it as deploy-relevant and ran the complete
pipeline, demonstrating that a mixed documentation and non-documentation
change cannot take the lightweight documentation-only path.

## Deployed revision configuration

`gcloud run services describe` reported the following state after the
successful delivery:

```text
latest ready revision: cloud-native-api-sha-e4d5c1c9-run-32653385587
production traffic:    100%
runtime account:        cloud-native-api-runtime@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com
container image tag:    e4d5c1c9edd46d20a68e61ad4e058e6707a34b7e
secret versions:        numeric version 2 for URL, username, and password
CPU / memory:           1 / 512Mi
maximum instances:      1
container concurrency:  20
```

The revision retained the Terraform-managed HTTP probes:

- startup and readiness: `/actuator/health/readiness` on port `8080`
- liveness: `/actuator/health/liveness` on port `8080`

This confirms that the image-only deployment preserved the runtime identity,
Secret Manager references, resources, probes, scaling, and concurrency rather
than replacing the service template with workflow defaults.

## Terraform ownership boundary

An initial post-deployment plan exposed workflow-owned revision metadata that
Terraform still wanted to remove. The lifecycle boundary was then narrowed to
ignore the deployed container image, explicit revision name, the known
`commit-sha` and `managed-by` template labels, client metadata, and traffic.
Unrelated labels and all structural service settings remain drift-detected.

After the corrected configuration was merged and the successful deployment
above completed, this command was repeated:

```powershell
terraform -chdir=terraform plan -input=false -no-color
```

The result was:

```text
No changes. Your infrastructure matches the configuration.
```

No apply followed the plan. The result demonstrates convergence between the
Terraform-owned service structure and the delivery-owned revision metadata,
image, and traffic.

## Controlled smoke-test failure

[GitHub Actions run 32654236868](https://github.com/Pierlu27/cloud-native-api/actions/runs/32654236868)
was dispatched manually from `main` with `force_smoke_failure=true`. It created
the isolated candidate:

```text
cloud-native-api-sha-e4d5c1c9-run-32654236868
```

The real readiness and Job API requests completed before the workflow emitted
the intentional error:

```text
Controlled smoke-test failure requested. Candidate will not be promoted.
```

The promotion and production-target verification steps were skipped. The
cleanup step still ran through `always()` and removed the temporary candidate
tag. A subsequent service description showed:

```text
latest ready revision: cloud-native-api-sha-e4d5c1c9-run-32654236868
production traffic:    100% cloud-native-api-sha-e4d5c1c9-run-32653385587
```

`latest ready` only means that the candidate container can run; it does not
mean that the revision receives production traffic. The failed candidate
remained at zero percent and the previously promoted revision continued to
serve the normal service URL.

## Manual rollback rehearsal

The available revisions were inspected before changing traffic. The controlled
failure candidate was excluded, and traffic was moved from the current stable
revision to its preceding stable revision:

```powershell
gcloud run services update-traffic cloud-native-api `
  --project project-c42baf60-7736-408b-9ff `
  --region europe-west8 `
  --to-revisions "cloud-native-api-sha-ec5e9926-run-32652629259=100" `
  --quiet
```

Cloud Run reported 100% traffic on the selected revision. The public readiness
and Job API endpoints both returned HTTP 200. The same traffic-only command was
then used to restore the current stable revision:

```text
cloud-native-api-sha-e4d5c1c9-run-32653385587 = 100%
readiness endpoint                              = HTTP 200
Job API endpoint                                = HTTP 200
```

The rehearsal did not build an image, create a revision, or delete any
revision. It only changed the target of the stable service URL and then restored
the original target.

## Documentation-only delivery behavior

This document, its index entry, and the related spec status update formed the
documentation-only change used to verify the lightweight pull-request path in
[GitHub Actions run 32655487076](https://github.com/Pierlu27/cloud-native-api/actions/runs/32655487076).

The pull-request run completed with:

```text
Classify changes             SUCCESS
Secret scan                  SUCCESS
Build and test               SKIPPED
Dependency scan              SKIPPED
Build dependency scan        SKIPPED
Static analysis              SKIPPED
Build and publish image      SKIPPED
Deploy candidate and promote SKIPPED
```

GitHub reported the pull request as `MERGEABLE` with merge state `CLEAN`.
Therefore the required `Build and test` check resolved without running the real
build, while secret scanning remained active and the expensive jobs consumed no
runner time.

Pull request #24 was merged locally with `--no-ff` and pushed to `main` as
commit:

```text
e61de89f5b280d2dffe58964c58ee82806f4e191
```

A workflow query scoped to that exact commit returned an empty result (`[]`),
demonstrating that the `push` trigger's documentation `paths-ignore` rule did
not create a main-branch CI run. The post-merge comparison also remained
unchanged:

```text
latest created revision: cloud-native-api-sha-e4d5c1c9-run-32654236868
production revision:     cloud-native-api-sha-e4d5c1c9-run-32653385587 (100%)
latest registry digest:  sha256:d184c5969ee9144c965ed823e7498f88fcce2a7efc679773287ba3a2c9efd342
registry update time:    2026-08-23T17:19:02Z
```

The documentation-only merge therefore published no image and created no
Cloud Run revision. Pull requests retain lightweight validation and secret
scanning, while protected-main documentation merges do not repeat work already
validated by the pull request.

## Evidence safety

The evidence contains no secret payload, access token, generated credentials
file, Terraform state, saved plan, or local `terraform.tfvars` content.
Screenshots are optional; textual commands, resource identifiers, workflow
links, and sanitized outputs are the reproducible source of truth.
