# Phase 7 Supabase PostgreSQL Verification

Verification date: 2026-08-20.

Phase 7 replaced the local-only database dependency for the deployed service
with a managed Supabase Free PostgreSQL project. Supabase is external to GCP and
was configured independently from Terraform.

## Connection architecture

Cloud Run connected through the Supavisor Session Pooler rather than a direct,
unpooled PostgreSQL endpoint. The JDBC connection required TLS through
`sslmode=require`.

The Spring Boot Hikari pool was constrained for the small serverless workload:

```text
maximum-pool-size: 5
minimum-idle: 0
```

Together with Cloud Run's maximum of one instance, this bounds the application's
database connections and avoids creating a permanent idle pool when the service
scales to zero.

## Functional evidence

- Supabase provisioned the PostgreSQL database on the Free plan.
- The application started successfully against the Session Pooler connection.
- Hibernate created/validated the application schema on the managed database.
- Public Swagger requests verified all five Job API endpoints against Supabase.
- Created data remained available across separate requests, demonstrating
  managed database persistence rather than local container storage.
- Cloud Run revision `cloud-native-api-00004-2p6` returned `UP` during the
  original Phase 7 verification.

Connection values were externalized as runtime environment variables during
this phase and were never committed. The verification record contains no host
credential, username, password, or complete JDBC value.

## Accepted Free-plan constraints

At the time of Phase 7, the project accepted the recorded Free-plan limits of
500 MB database storage, 5 GB egress, and automatic pause after one week of
inactivity. These values are historical evidence of the decision and must be
rechecked against Supabase's current plan before relying on them operationally.

The inactivity pause was accepted instead of adding synthetic traffic or a paid
scheduler. A paused database can temporarily make the application appear
unhealthy until the external service resumes.

## Evolution in Phase 8

Phase 8 preserved the same Supabase Session Pooler and TLS connection but moved
the three datasource values from plaintext Cloud Run environment configuration
to Secret Manager references. Terraform manages the secret containers, the
secret-scoped runtime IAM grants, and the Cloud Run references; it deliberately
does not manage secret payload versions or the Supabase project.

This evolution completes the security work that earlier roadmap text assigned
to a later secrets-management phase. It does not change the historical fact
that Phase 7 first verified the managed database using externalized runtime
variables.
