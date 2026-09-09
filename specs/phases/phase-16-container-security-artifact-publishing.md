# Spec: Phase 16 - Container Security & Artifact Publishing

Status: complete. Acceptance verified on 2026-09-06; final documentation
recorded on 2026-09-08. See the [verification record](../../docs/phase-16-verification.md)
for run references, registry digests, production traffic, and credential checks.

## 1. Goal

Introduce Trivy security gates for the application image and Terraform
configuration, then transfer development-image publishing from GitHub Actions
to the Jenkins Docker Agent introduced in Phase 13. Jenkins and GitHub Actions
continue to share the existing Artifact Registry repository, but own different
image packages inside it:

- Jenkins owns `cloud-native-api-dev` from the `develop` branch;
- GitHub Actions owns `cloud-native-api-prod` from the `main` branch.

Both publishers must retain the immutable full commit SHA as the deployment and
rollback reference. Each package may also expose its own mutable `latest` alias
for human convenience; Cloud Run delivery must never rely on that alias.

## 2. Existing baseline

The repository already provides:

- the complete Phase 15 Jenkins CI sequence on the `build-test` agent;
- a separate static Docker Agent with the Docker CLI and access to the trusted
  host Docker daemon;
- a GitHub Multibranch job that discovers internal branches and pull requests;
- one Terraform-managed Artifact Registry Docker repository named
  `cloud-native-api`;
- GitHub Actions WIF authentication and a dedicated publisher identity; and
- GitHub Actions image publishing and Cloud Run delivery for both `develop` and
  `main`.

Phase 16 must preserve the Phase 15 gates while adding the Docker Agent block.
It intentionally changes publisher ownership: Jenkins becomes the development
publisher, while GitHub Actions remains the production publisher and deployer.

## 3. Scope

In scope:

- changing the root pipeline to top-level `agent none`, with one sequential
  `build-test` block retaining Phase 15 and one sequential `docker` block for
  container work;
- performing an explicit SCM checkout on the Docker Agent because agent
  workspaces are not shared;
- building and scanning a commit-SHA-tagged application image for trusted
  internal branches and pull requests;
- installing pinned Trivy `0.74.0` in the Docker Agent image;
- scanning the application image for `HIGH` and `CRITICAL` vulnerabilities;
- scanning `terraform/` for `HIGH` and `CRITICAL` misconfigurations;
- producing and archiving JSON and table reports for both Trivy scans;
- persisting Trivy database, checks-bundle, and scan-cache data in a named
  Docker volume;
- publishing `cloud-native-api-dev` only for a direct `develop` branch build,
  never for a pull-request or feature-branch build;
- retaining GitHub Actions validation for all existing events while limiting
  its image publishing and Cloud Run delivery to `main` and the
  `cloud-native-api-prod` package;
- allowing an environment-local `latest` alias for both image packages while
  keeping the full SHA tag mandatory; and
- provisioning a dedicated Jenkins publisher identity through Terraform while
  creating and handling its credential outside Terraform.

Out of scope:

- Jenkins Cloud Run deployment logic, which belongs to Phase 17;
- changing the production deployment owner from GitHub Actions;
- semantic versioning or tagging strategies beyond the full SHA and the
  package-local `latest` convenience alias;
- dynamic agent provisioning or a separate Trivy agent;
- replacing the existing Artifact Registry repository; and
- redesigning application code, Gradle quality gates, or the Phase 15 Jenkins
  stages. A genuine blocking baseline vulnerability may require a separately
  reviewed remediation before the clean Phase 16 run can pass.

During the transition between Phases 16 and 17, a successful Jenkins run
publishes the development image but does not yet update the development Cloud
Run service. The last promoted development revision remains active until Phase
17 adds Jenkins delivery.

## 4. Functional requirements

1. The root `Jenkinsfile` must use top-level `agent none`. A parent
   `Continuous Integration` stage must allocate `build-test` once and retain
   the complete, ordered Phase 15 stage sequence and publication behavior.
2. A following `Container Security & Publishing` stage must allocate the
   existing `docker` label once and contain ordered Checkout, Docker Build,
   Trivy Image Scan, Trivy IaC Scan, and Docker Push child stages.
3. The Docker Agent checkout must use `checkout scm`, derive the exact checked
   out commit through `git rev-parse HEAD`, and reject any value that is not a
   lowercase 40-character hexadecimal SHA. It must not reuse the workspace or
   `GIT_COMMIT` value from the Build/Test Agent.
4. `Docker Build` must run for trusted internal branch and pull-request jobs and
   build the repository-owned application `Dockerfile`. The local image must be
   tagged with the validated full SHA. The development registry package name is
   `cloud-native-api-dev`.
5. Before finalizing the gate, pinned Trivy `0.74.0` must scan the current
   application image and Terraform baseline. Any existing `HIGH` or `CRITICAL`
   result must be classified as a genuine finding, an intentional design, or an
   identification defect. No ignore rule or application change may be added
   without an explicit reviewed reason.
6. `Trivy Image Scan` must use `trivy image --scanners vuln` and evaluate only
   `HIGH,CRITICAL` findings. It must create one JSON source report, convert that
   report to a human-readable table, and apply exit code `1` to the converted
   result so both artifacts still exist when the gate fails.
7. `Trivy IaC Scan` must use `trivy config` against `terraform/` and evaluate
   only `HIGH,CRITICAL` misconfigurations. It must likewise create one JSON
   source report, convert it to a table, and apply exit code `1` to the
   converted result.
8. Each Trivy stage must archive its JSON and table reports from a stage
   `post { always { ... } }` block. An operational Trivy error must also fail
   the stage rather than being interpreted as a clean scan.
9. The Docker Push stage must run only when all earlier stages pass, the
   Multibranch job is a direct `develop` branch build, and no change-request
   context is present. Feature branches, `main`, and every pull request must
   build and scan but skip publishing from Jenkins.
10. A successful Jenkins development publication must push both
    `cloud-native-api-dev:<full-SHA>` and `cloud-native-api-dev:latest` inside
    the existing `cloud-native-api` Artifact Registry repository. The full SHA
    is the immutable source of truth; `latest` is only a movable alias.
11. GitHub Actions must continue to run its existing validation gates, but its
    image-publish and Cloud Run delivery jobs must run only on `main`. They must
    publish `cloud-native-api-prod:<GITHUB_SHA>` and
    `cloud-native-api-prod:latest`, then pass the SHA-tagged image to the
    existing production delivery workflow. A `develop` push must not publish or
    deploy through GitHub Actions.
12. Terraform must map the development Cloud Run service to
    `cloud-native-api-dev` and production to `cloud-native-api-prod` when
    creating services in a new target configuration. Existing delivery-owned
    image and traffic drift remains ignored as already decided in Phase 8.
13. Terraform must create a separate `jenkins-artifact-publisher` service
    account and grant it `roles/artifactregistry.writer` only on the existing
    `cloud-native-api` repository. Terraform must not create, read, accept, or
    output the service-account private key.
14. The Jenkins publisher key must be created out of band, Base64-encoded, and
    stored as secret text in the JCasC-managed Credentials Store under stable ID
    `artifact-registry-publisher-key-base64`. Only a placeholder may appear in
    the tracked environment example.
15. Docker Push must bind that credential only around registry authentication
    and push commands. It must authenticate using `_json_key_base64` and
    `--password-stdin`, use a temporary `DOCKER_CONFIG`, avoid echoing the
    credential, and always perform logout and local configuration cleanup.
16. The Docker Agent must store Trivy data under
    `/home/jenkins/.cache/trivy`, owned by the unprivileged `jenkins` user and
    backed by a dedicated named Compose volume. Pipeline commands must select
    that directory explicitly. The current single Docker Agent executor keeps
    filesystem-cache access sequential.
17. Stages must remain sequential and fail fast. Docker build, either Trivy
    gate, authentication, or push failure must mark the run as `FAILURE`; report
    publication and credential cleanup may still run to preserve diagnostics
    and remove temporary state.

## 5. Non-functional requirements

- CI gate: Docker Push must be unreachable when either Trivy scan fails, while
  both reports remain available for diagnosis.
- Security: the Jenkins publisher is separate from the GitHub Actions publisher
  and receives only repository-scoped writer access. Because both identities
  share one repository, the two package names provide operational ownership but
  not a hard package-level IAM boundary.
- Security: the local service-account key is an explicitly accepted fallback
  for a Jenkins installation without an external OIDC identity provider. It is
  a long-lived credential and must remain outside source control, Terraform
  inputs/state, agent images, console output, build artifacts, and persistent
  Docker configuration.
- Security: the key must have a documented rotation, disable, and deletion
  procedure. It must be rotated immediately after suspected exposure and
  removed when the local Jenkins publisher is no longer used.
- Traceability: every published image must retain the full source commit SHA.
  Delivery and rollback use that immutable tag; neither environment may deploy
  from `latest`.
- Reproducibility: the Trivy version must be pinned in the Docker Agent image,
  and both CI implementations must derive their package names consistently from
  version-controlled configuration.
- Observability: JSON and table reports must be reachable from the classic
  Jenkins build page without an external dashboard.
- Compatibility: `HIGH,CRITICAL` is conceptually aligned with the existing
  high-severity release policy, but Trivy vendor severity is not identical to
  OWASP Dependency-Check's numeric CVSS `7.0` threshold. The distinction must
  be documented rather than described as the same calculation.

## 6. Acceptance criteria

- [x] a clean Jenkins branch or pull-request run preserves every Phase 15 stage,
      then checks out and builds the SHA-tagged application image on the Docker
      Agent
- [x] a feature-branch or pull-request run executes both Trivy gates and skips
      Docker Push without binding the Artifact Registry credential
- [x] Trivy Image Scan produces archived JSON and table reports and blocks the
      pipeline on `HIGH` or `CRITICAL` image vulnerabilities
- [x] a temporary branch containing a deliberately vulnerable image fixture
      fails Trivy Image Scan and never reaches Docker Push
- [x] Trivy IaC Scan produces archived JSON and table reports for `terraform/`
      and blocks the pipeline on `HIGH` or `CRITICAL` misconfigurations
- [x] a different temporary branch containing a Trivy-0.74.0-verified Terraform
      fixture fails Trivy IaC Scan and never reaches Docker Push; the fixture
      must not use the intentional public Cloud Run invoker policy
- [x] a clean direct `develop` run pushes
      `cloud-native-api-dev:<full-SHA>` and `cloud-native-api-dev:latest` to the
      existing Artifact Registry repository
- [x] a `develop` push runs GitHub Actions validation but skips its image publish
      and Cloud Run deployment jobs
- [x] a clean `main` push runs Jenkins scans without a Jenkins push, while
      GitHub Actions publishes `cloud-native-api-prod:<GITHUB_SHA>` and
      `cloud-native-api-prod:latest` and completes production delivery using the
      SHA tag
- [x] Artifact Registry evidence shows separate development and production
      packages, each with its expected SHA and package-local `latest` alias
- [x] the Jenkins registry credential is absent from source, logs, artifacts,
      agent images, and the persistent Docker configuration
- [x] recreating the Docker Agent without deleting the named Trivy volume
      preserves real database and checks-bundle data reused by a later scan

## 7. Deliverables

- workflow: extended root `Jenkinsfile` with the two agent-owned sequential
  blocks, Docker build, Trivy gates, report publication, branch policy, and
  scoped registry authentication;
- workflow: adjusted GitHub Actions image publishing and delivery ownership for
  production only;
- Jenkins infrastructure: pinned Trivy binary, writable persistent Trivy cache,
  and JCasC-managed publisher credential;
- Terraform: environment-specific initial image package mapping, dedicated
  Jenkins publisher identity, existing-repository writer binding, validated
  non-secret inputs, and non-sensitive outputs;
- documentation: updated Jenkins, security, Terraform, architecture/ownership,
  decision, index, and Phase 16 verification documentation.

No service-account private key, Base64 payload, temporary negative fixture, or
generated Trivy report is a committed deliverable.

## 8. Evidence

- one clean Jenkins feature or PR run showing both agents, all Phase 15 gates,
  both Trivy gates, archived JSON/table reports, and a skipped Docker Push;
- one clean direct `develop` run showing Jenkins publish both development tags
  while GitHub Actions skips image publishing and delivery;
- one controlled image-vulnerability run showing Trivy Image Scan fail and all
  later publishing stages skipped;
- one separate controlled Terraform-misconfiguration run showing Trivy IaC Scan
  fail and Docker Push skipped;
- before/after Docker Agent recreation evidence showing real Trivy database and
  checks-bundle data preserved and reused;
- Artifact Registry listing showing distinct `cloud-native-api-dev` and
  `cloud-native-api-prod` packages with their SHA and `latest` tags; and
- one `main` run showing Jenkins skip publishing and GitHub Actions publish and
  deploy the SHA-tagged production package successfully.

Evidence is recorded textually in the repository; screenshots are optional and
not required for phase completion.

## 9. Risks and mitigations

- risk: running Trivy without persistent data repeatedly downloads databases or
  policy bundles, increasing latency and exposure to remote rate limits.
  mitigation: mount a named cache volume, select it explicitly, and prove reuse
  after Docker Agent recreation.
- risk: simultaneous Trivy processes can contend for a filesystem cache lock.
  mitigation: retain one executor on the static Docker Agent and run the two
  scans sequentially; revisit an external cache only if concurrency is added.
- risk: a current baseline image or the intentional Terraform configuration can
  already contain a blocking finding.
  mitigation: scan and classify the baseline before choosing fixtures or
  exceptions; remediate genuine findings and require narrowly reviewed reasons
  for any ignore rule.
- risk: a mutable `latest` alias can move and cannot prove which source revision
  is running.
  mitigation: keep it package-local and informational; build, evidence,
  deployment, and rollback always use the full SHA.
- risk: a service-account key is a long-lived bearer credential and cannot
  provide the same issuer/subject audit trail as Workload Identity Federation.
  mitigation: use a Jenkins-only least-privilege identity, store the key only in
  the local Credentials Store, bind it for the shortest stage, clean Docker
  state, document rotation/revocation, and prefer WIF if Jenkins later gains a
  trusted OIDC provider.
- risk: repository-level IAM technically lets either publisher write both image
  packages even though ownership is separated by convention.
  mitigation: use distinct identities and package names, audit publisher
  activity, and move to separate repositories if a hard authorization boundary
  becomes necessary.
- risk: Phase 16 stops GitHub Actions development delivery before Jenkins
  delivery exists.
  mitigation: retain the last healthy development revision, make the temporary
  transition explicit, and implement Jenkins candidate deployment and
  promotion in Phase 17 before expecting new development commits to reach Cloud
  Run automatically.
- risk: negative-test branches could retain a known-vulnerable base or insecure
  Terraform fixture.
  mitigation: use synthetic or deliberately obsolete test inputs only, never
  real credentials, delete the branches after evidence is captured, and never
  merge them into `develop` or `main`.

## 10. Definition of done (phase)

- [x] implementation complete on both static Jenkins agents without regressing
      the Phase 15 CI stages
- [x] Jenkins owns development image publishing and GitHub Actions owns
      production image publishing and delivery
- [x] clean, no-push, image-failure, and IaC-failure paths behave as specified
- [x] both image packages expose immutable SHA tags and independent `latest`
      aliases, while deployment continues to use SHA
- [x] the Jenkins credential boundary and real persistent Trivy cache reuse are
      verified
- [x] documentation, ownership diagrams, decisions, and textual Phase 16
      evidence are updated
