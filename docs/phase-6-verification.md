# Phase 6 Cloud Run Verification

Verification dates: 2026-08-20 and 2026-08-21.

Phase 6 proved that the Artifact Registry image could run as a public HTTPS
service on Cloud Run. Deployment was manual; automatic delivery after an image
publication remained out of scope.

## Historical deployed service

- service: `cloud-native-api`
- region: `europe-west8`
- public URL used for verification:
  `https://cloud-native-api-630606381542.europe-west8.run.app`
- verified revision: `cloud-native-api-00005-knj`
- immutable image tag:
  `d893465c3bb43001fe8d9c420263a4e7b89a4292`
- previous retained revision: `cloud-native-api-00004-2p6`
- traffic: 100 percent to the latest ready revision

The two retained revisions demonstrate Cloud Run's automatic revision model:
executing a deployment with changed configuration or an image creates a new
immutable revision. It does not mean Cloud Run watches Artifact Registry or
deploys automatically when the `latest` tag moves; Phase 9 owns that delivery
automation.

## Runtime verification

The public service returned `UP` from:

```text
/actuator/health
/actuator/health/readiness
/actuator/health/liveness
```

Public Swagger requests exercised the Job API create, read, update, and delete
flow against the external Supabase PostgreSQL database. This verified public
routing, application startup, runtime configuration, schema access, and database
persistence together.

Cloud Run was configured with:

- zero minimum instances and one maximum instance at service level;
- zero minimum instances and one maximum instance at revision level;
- concurrency limit `20`;
- startup and readiness HTTP probes on `/actuator/health/readiness`;
- liveness HTTP probe on `/actuator/health/liveness`;
- application port `8080` as the only container port.

The probe endpoints are supplied by Spring Boot Actuator. Docker and Cloud Run
invoke them but do not create them. Unlike a TCP probe, the HTTP probes verify
that the application reports the expected readiness or liveness state rather
than only accepting a network connection.

Successful public requests produced Cloud Run request logs and native request
count and latency metrics, satisfying the phase's basic observability check.

## Evolution in Phase 8

Phase 8 migrated the datasource configuration to Secret Manager, assigned the
dedicated `cloud-native-api-runtime` identity, and created healthy revision
`cloud-native-api-00006-9pd`. It then imported the service and public invoker
member into Terraform. The current canonical URL is obtained with:

```bash
terraform -chdir=terraform output -raw cloud_run_service_url
```

The Phase 6 URL and revision above remain historical evidence; the Phase 8
verification document records the current Terraform-managed configuration.
