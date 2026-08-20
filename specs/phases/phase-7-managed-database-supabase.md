# Spec: Phase 7 - Managed Database (Supabase PostgreSQL)

## 1. Goal

Move the application's database from a local containerized PostgreSQL instance to a managed PostgreSQL instance hosted on Supabase, so that Cloud Run connects to a production-grade, managed database without provisioning a paid GCP database service such as Cloud SQL.

## 2. Scope

In scope:

- provisioning a Supabase project and its underlying PostgreSQL database (Free tier)
- securing the connection using TLS and Supabase-issued credentials
- connecting Cloud Run to Supabase Postgres using the Supavisor Session Pooler
- migrating connection configuration from the Phase 2 Docker Compose setup to the Supabase connection string
- basic connection pooling configuration appropriate for a serverless, autoscaling Cloud Run service
- verifying schema creation and data persistence against the managed Supabase instance
- documenting the Free tier limitations relevant to this project (storage, egress, inactivity pause)

Out of scope:

- provisioning Supabase through Terraform (optional future improvement; not required for this phase — see note in section 8)
- Secret Manager integration for storing database credentials (Phase 9, though credentials must not be hardcoded even in this phase)
- Supabase-specific features beyond the Postgres database itself (Auth, Storage, Edge Functions, Realtime)
- any GCP-managed database service (Cloud SQL is explicitly not part of this project)

## 3. Functional requirements

1. A Supabase project must be created on the Free tier, with a PostgreSQL database provisioned automatically as part of the project.
2. The Cloud Run service must connect to the Supabase database using the Supavisor Session Pooler connection string, not a direct unpooled connection.
3. Database connection details (host, port, database name, user, password) must be supplied to the application via environment variables, consistent with the externalized configuration approach established in Phase 2.
4. The application must successfully run its schema initialization (e.g. Hibernate DDL or a migration tool) against the Supabase-hosted database on first startup.
5. Existing Job API endpoints from Phase 1 must continue to work correctly when the application is connected to Supabase instead of the local Docker Compose database.
6. Connection pooling must be configured at the application level (e.g. HikariCP pool size limits) to stay within Supabase's default pool and max client connection limits for the Free tier project size.
7. The connection must use TLS, relying on Supabase's default encrypted connection rather than a plain-text connection.

## 4. Non-functional requirements

- CI gate: no changes to the existing CI pipeline are required in this phase; this is an infrastructure and configuration change verified through manual and integration testing against the real Supabase instance.
- Security: credentials must never be committed to the repository and must be passed to Cloud Run as environment variables or secrets at deploy time (full Secret Manager integration follows in Phase 9); since Supabase is reachable over the public internet by design, TLS and credential secrecy are the primary controls, rather than network-level isolation like a private VPC.
- Observability: basic Supabase project metrics (database size, active connections, egress usage) must be checked periodically in the Supabase dashboard to avoid silently exceeding Free tier limits.

## 5. Acceptance criteria

- [ ] Supabase project created with a PostgreSQL database provisioned on the Free tier
- [ ] Cloud Run service successfully connects to Supabase Postgres via the Supavisor pooled connection string
- [ ] application schema is created successfully on first connection to the managed Supabase database
- [ ] all five Job API endpoints verified working against Supabase (not the local database)
- [ ] connection pool configured with an explicit maximum size, verified to stay within Supabase's default connection limits for the project's compute size
- [ ] connection confirmed to use TLS (no plain-text fallback)
- [ ] Free tier limitations (500 MB storage, 5 GB egress, auto-pause after 1 week of inactivity) documented and understood as an accepted constraint for this phase

## 6. Deliverables

- code: updated application configuration (`application.yml` / environment variable wiring) to support the Supabase connection string and pool sizing
- workflow: no CI/CD workflow changes in this phase (deployment step will be extended when Phase 10 formalizes Continuous Delivery)
- documentation: updated `docs/deployment.md` describing how the Cloud Run service connects to Supabase, the Supavisor pooling setup, and the rationale for choosing Supabase over Cloud SQL (cost)

## 7. Evidence

- Supabase dashboard screenshot showing the provisioned project, database size, and connection pooling settings
- screenshot or log confirming a successful Cloud Run request that reads/writes data through Supabase Postgres
- sample API requests (create, read, update, delete a Job) executed against the Cloud Run + Supabase setup
- connection string format used, confirming the Supavisor pooler host/port is used (not the direct database host)
- note or screenshot confirming TLS is used for the database connection

## 8. Risks and mitigations

- risk: Supabase's Free tier project automatically pauses after 1 week of inactivity, which would make the application appear broken if no traffic has hit it recently.
  mitigation: document this behavior explicitly in `docs/deployment.md` and accept the pause as a known Free tier trade-off. Do not add a paid scheduler or other always-on resource just to avoid the pause.
- risk: Cloud Run's autoscaling can spawn many container instances quickly, each potentially opening its own connection pool, which can exhaust Supabase's Free tier connection limits (e.g. around 60 max connections on the smallest tier).
  mitigation: keep the per-instance connection pool small, always connect through the Supavisor pooler rather than directly to the database, and bound Cloud Run concurrency/max instances accordingly.
- risk: the Free tier's 500 MB storage and 5 GB egress limits could be exceeded unexpectedly as usage grows, with no automatic scaling path without upgrading to a paid plan.
  mitigation: monitor database size and egress periodically from the Supabase dashboard, and treat any approach toward these limits as a signal to revisit the decision recorded in `docs/decisions.md`.
- risk: since Supabase is external to GCP, it is not covered by GCP's IAM, VPC, or Cloud SQL-specific documentation and tooling, which could create confusion when following GCP-centric guides.
  mitigation: treat Supabase explicitly as an external managed service in all documentation, with its own credentials and security model, distinct from the GCP resources managed by Terraform.

## 9. Definition of done (phase)

- [ ] implementation complete (Supabase project provisioned, Cloud Run connected via Supavisor pooler, application configuration updated)
- [ ] tests pass (existing Job API endpoints verified functionally correct against the Supabase-backed deployment)
- [ ] documentation updated (`docs/deployment.md` describing the Supabase connection setup, pooling configuration, and the cost rationale for choosing it over Cloud SQL)
- [ ] decisions recorded (e.g. Supabase vs. Cloud SQL choice, pooling mode, Free tier trade-offs accepted) in `docs/decisions.md` or equivalent
