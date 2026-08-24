# Phase 10 Environment Separation Verification

Verification date: 2026-08-24.

This document records the reproducible evidence for the development and
production separation introduced in Phase 10. It uses workflow links,
sanitized IAM and Cloud Run output, and HTTP results instead of mandatory
Console screenshots.

## Development delivery

[GitHub Actions run 32757788701](https://github.com/Pierlu27/cloud-native-api/actions/runs/32757788701)
completed successfully after the Phase 10 changes were merged into `develop`.
The run completed all CI and security gates, published the immutable image for
commit `3e6108f88e548ddab25fdbcfe65241ed7412b791`, and automatically deployed:

```text
service:  cloud-native-api-dev
revision: cloud-native-api-dev-sha-3e6108f8-run-32757788701
runtime:  cloud-native-api-dev-runtime@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com
traffic:  100%
```

The deployment required no GitHub Environment approval. Its candidate was
created without normal traffic, tested through a temporary
`candidate-3e6108f8` traffic tag, promoted by exact revision name, verified as
the 100% traffic target, and then had the temporary tag removed.

## Production approval and delivery

Pull request [#28](https://github.com/Pierlu27/cloud-native-api/pull/28)
promoted the already verified Phase 10 tree from `develop` to `main`. Its
pull-request run completed the CI and security gates while image publishing and
deployment were intentionally skipped: only a `push` or manual run on
`develop` or `main` may perform delivery.

After the merge, [GitHub Actions run 32759177812](https://github.com/Pierlu27/cloud-native-api/actions/runs/32759177812)
published the image for main commit
`5f915de5d6b21f4f5826acb44f427c2d92eb7262`. The production deployment then
paused at the protected `production` GitHub Environment until its configured
reviewer approved it. No Cloud Run deployment step started before approval.

After approval, the same candidate, smoke-test, exact-revision promotion,
traffic verification, and tag-cleanup sequence completed successfully:

```text
service:  cloud-native-api-prod
revision: cloud-native-api-prod-sha-5f915de5-run-32759177812
runtime:  cloud-native-api-prod-runtime@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com
traffic:  100%
```

The two environments therefore have distinct service URLs, revision histories,
runtime identities, and branch-controlled delivery paths.

## Database isolation

A uniquely identifiable record was created through the development API only:

```text
title: phase-10-isolation-5f915de5
id:    19d06577-8b39-4fea-bde8-c0ccee4bed27
```

Reading that exact UUID through the two environment URLs produced:

```text
GET cloud-native-api-dev/.../19d06577-8b39-4fea-bde8-c0ccee4bed27  -> HTTP 200
GET cloud-native-api-prod/.../19d06577-8b39-4fea-bde8-c0ccee4bed27 -> HTTP 404
```

The production error explicitly reported that the UUID was not found. This is
runtime evidence that the two applications query separate Supabase databases,
not merely that their Cloud Run templates reference differently named secrets.
The non-sensitive test record is retained temporarily in development until the
Phase 10 evidence change is reviewed.

## Secret access boundaries

`gcloud secrets get-iam-policy` was run for the URL, username, and password
containers of both environments. No secret payload was requested. All three
development policies contained only:

```text
role:   roles/secretmanager.secretAccessor
member: serviceAccount:cloud-native-api-dev-runtime@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com
```

All three production policies contained only:

```text
role:   roles/secretmanager.secretAccessor
member: serviceAccount:cloud-native-api-prod-runtime@project-c42baf60-7736-408b-9ff.iam.gserviceaccount.com
```

The development runtime therefore has no resource-level accessor binding on
the production database secrets, and the production runtime has no equivalent
binding on the development secrets.

## Branch-scoped deployer impersonation

The applied service-account IAM policies were also read directly from Google
Cloud. The development deployer grants `roles/iam.workloadIdentityUser` only
to:

```text
principalSet://iam.googleapis.com/projects/630606381542/locations/global/workloadIdentityPools/github-actions/attribute.environment/development
```

The production deployer grants the same role only to:

```text
principalSet://iam.googleapis.com/projects/630606381542/locations/global/workloadIdentityPools/github-actions/attribute.environment/production
```

The Workload Identity Provider maps `refs/heads/develop` to `development` and
`refs/heads/main` to `production`. Consequently, a token from `develop` is not
a member of the principal set allowed to impersonate the production deployer,
and the inverse is also true.

## Remaining Phase 10 work

The historical unsuffixed `cloud-native-api` service remains available as the
planned rollback fallback. Phase 10 is not complete until its rollback window
is explicitly closed, still-useful Terraform comments are consolidated into
the environment-aware resources, the retirement plan is reviewed and applied,
and the resulting Terraform plan is a no-op.

## Evidence safety

This evidence contains no database URL, username, password, secret payload,
OIDC token, generated credential file, Terraform state, saved plan, or local
`terraform.tfvars` content. Resource identifiers, workflow links, HTTP status
codes, and IAM member names are intentionally retained because they make the
environment boundaries reproducible and reviewable.
