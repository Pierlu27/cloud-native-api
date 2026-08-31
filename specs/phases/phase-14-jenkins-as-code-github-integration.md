# Spec: Phase 14 - Jenkins as Code & GitHub Integration

## 1. Goal

Configure Jenkins entirely through code using Jenkins Configuration as Code (JCasC), and connect it to GitHub through a Multibranch Pipeline, so that branches and pull requests are discovered and built automatically, without manual job configuration or a repeatable setup wizard.

## 2. Scope

In scope:

- a JCasC YAML file (`jenkins.yaml`) defining system configuration, security realm, authorization strategy, and credentials, applied automatically at Controller startup via `CASC_JENKINS_CONFIG`
- credentials defined in JCasC sourced from environment variables, never hardcoded in the YAML file
- the existing Build/Test and Docker static-node definitions managed by JCasC, while their generated inbound secrets remain local runtime values
- a Multibranch Pipeline job configured to discover branches and pull requests from the project's GitHub repository
- a GitHub webhook forwarded through a temporary local-development relay to the Jenkins Controller, so branch/PR changes trigger pipeline scans without polling or exposing the complete local Jenkins UI
- an initial `Jenkinsfile` in the repository root (or a dedicated `jenkins/` folder), recognized automatically by the Multibranch Pipeline

Out of scope:

- the actual build, test, and security stages inside the `Jenkinsfile` (Phase 15)
- container image scanning and artifact publishing (Phase 16)
- deployment logic (Phase 17)
- GitHub Organization-level scanning (multiple repositories) — this phase covers a single repository's Multibranch Pipeline

## 3. Functional requirements

1. The Jenkins Controller must load its configuration from a version-controlled `jenkins.yaml` file at startup, via the `CASC_JENKINS_CONFIG` environment variable, without requiring the setup wizard to run.
2. The JCasC configuration must define the security realm and authorization strategy (e.g. a local admin user with a password sourced from an environment variable, not hardcoded in the YAML).
3. The JCasC configuration must define the GitHub credential (personal access token or equivalent) used by the Multibranch Pipeline, with the token value sourced from an environment variable, never committed in plain text.
4. A Multibranch Pipeline job must be created (via JCasC or, if not fully expressible in JCasC, documented as a one-time manual step) pointing at the project's GitHub repository as its branch source.
5. The Multibranch Pipeline must be configured to discover both branches and pull requests, with the `Jenkinsfile` path set to its actual location in the repository.
6. A GitHub webhook must be configured on the repository, pointing to `<jenkins-url>/github-webhook/`, triggering on push and pull request events.
7. Pushing a new branch containing a `Jenkinsfile` must automatically create a corresponding job under the Multibranch Pipeline, without any manual Jenkins configuration for that branch.
8. Opening a pull request must trigger a corresponding pipeline run for that pull request, discoverable in the Multibranch Pipeline's view.
9. JCasC must define the existing `build-test-agent` and `docker-agent` nodes so a fresh Controller volume recreates their names, labels, executor counts, remote roots, and inbound launch configuration without manual UI configuration. Their Jenkins-generated connection secrets must remain outside the committed YAML.

## 4. Non-functional requirements

- CI gate: not yet meaningful in this phase, since the `Jenkinsfile` itself contains no build/test logic yet; the gate here is that the Multibranch Pipeline correctly discovers and triggers for every relevant branch/PR event.
- Security: the GitHub token used by Jenkins must be scoped with least privilege: repository metadata, contents, and pull-request read access for discovery and checkout, plus commit-status write access for reporting Jenkins results. Webhook administration remains excluded because the webhook is configured manually.
- Local webhook boundary: the relay is only a development bridge to the local Controller, must not be treated as a production ingress, and its channel URL must remain outside version control.
- Observability: JCasC configuration drift must be detectable — any manual change made through the Jenkins UI that conflicts with `jenkins.yaml` must be reverted the next time the configuration is reloaded, and this behavior must be demonstrated at least once.

## 5. Acceptance criteria

- [x] Jenkins Controller starts with configuration applied automatically from `jenkins.yaml`, with no manual setup wizard interaction required
- [x] the admin user and its password are defined in JCasC via an environment variable, not a literal value in the YAML file
- [x] the GitHub credential used by the Multibranch Pipeline is defined in JCasC via environment variables
- [x] a fresh Controller volume recreates both static-node definitions from JCasC without manual node configuration
- [x] the Multibranch Pipeline job exists and discovers eligible repository branches and open pull requests containing the configured `Jenkinsfile`
- [x] pushing a new branch with a `Jenkinsfile` triggers an automatic scan and creates a job for that branch without manual intervention
- [x] opening a pull request triggers a corresponding pipeline run, visible in the Multibranch Pipeline's PR view
- [x] the GitHub webhook delivery log shows a successful delivery to the temporary relay, and the relay/Jenkins logs confirm forwarding to `/github-webhook/`
- [x] a manual system-message change made through the Jenkins UI is reverted after reloading JCasC, confirming that the YAML is the source of truth

## 6. Deliverables

- code: `jenkins.yaml` (JCasC configuration file), an initial minimal `Jenkinsfile` (e.g. a placeholder pipeline with a single stage, to be extended in Phase 15), any Dockerfile changes needed to bake `CASC_JENKINS_CONFIG` into the Controller image, and the local webhook-relay service configuration
- workflow: no GitHub Actions changes in this phase
- documentation: updated `docs/jenkins.md` describing the JCasC file structure, how credentials are sourced from environment variables, how the Multibranch Pipeline is configured, and how the GitHub webhook is wired

## 7. Evidence

Sanitized textual evidence is recorded in
`docs/phase-14-verification.md`; screenshots are not required. The verification
record includes the strict secret-resolution test, empty-volume node recreation,
successful relay delivery, automatic branch and PR builds, GitHub commit status,
and JCasC drift recovery. Pull request #45 records the implementation merge and
its successful `continuous-integration/jenkins/pr-merge` status.

- `jenkins.yaml` content (with secrets redacted/represented as environment variable references, not real values)
- Jenkins Controller startup log confirming JCasC configuration was applied successfully
- Multibranch Pipeline job view listing discovered branches and pull requests
- GitHub repository webhook delivery log plus relay/Jenkins log output showing the POST forwarded to `/github-webhook/`
- command output or API export (`/manage/configuration-as-code/export`) confirming a manual UI change was reverted after a JCasC reload

## 8. Risks and mitigations

- risk: hardcoding the GitHub token or admin password directly in `jenkins.yaml` would defeat the purpose of Configuration as Code by reintroducing a plain-text secret in version control.
  mitigation: source every credential value in JCasC from an environment variable (e.g. `${GITHUB_TOKEN}`), and verify by inspecting the committed `jenkins.yaml` that no real secret value is present.
- risk: relying on repository polling instead of a webhook would introduce delay and unnecessary load on both GitHub and Jenkins.
  mitigation: configure the GitHub webhook explicitly, forward it through the temporary local relay, and verify both GitHub delivery and Jenkins receipt rather than falling back to a periodic scan interval.
- risk: a public development relay channel is not authenticated production ingress and anyone who learns its URL may be able to send payloads through it.
  mitigation: keep the relay URL in the ignored local environment file, use it only for the controlled Phase 14 exercise, stop the relay when Jenkins is not being tested, and never treat it as a production endpoint.
- risk: if the Multibranch Pipeline job itself is created manually (because not every aspect of it is easily expressed in JCasC depending on the plugin version), configuration drift could occur if this step is not documented and repeatable.
  mitigation: document the exact manual steps (if any) required to recreate the Multibranch Pipeline job, so the setup remains reproducible even where JCasC coverage is incomplete.
- risk: granting the GitHub token excessive scopes (e.g. full repository administration) would violate least privilege for discovery and build reporting.
  mitigation: scope the token to this repository with only the reads required for metadata, contents, pull requests, and checkout plus `Commit statuses: Read and write`. Configure the webhook manually so Jenkins needs no webhook-management permission.

## 9. Definition of done (phase)

- [x] implementation complete (JCasC-driven Controller configuration, Multibranch Pipeline connected to GitHub, webhook configured and verified)
- [x] tests pass (a test branch and a test pull request both correctly trigger pipeline discovery and a run)
- [x] documentation updated (`docs/jenkins.md` describes JCasC structure, credential sourcing, and the Multibranch Pipeline/webhook setup)
- [x] decisions recorded in ADR-017, including JCasC ownership, Job DSL, token scope, PR strategy, and the local relay boundary
