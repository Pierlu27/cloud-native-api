# Spec: Phase 15 - Jenkins Continuous Integration

## 1. Goal

Turn the Phase 14 placeholder `Jenkinsfile` into a complete Jenkins CI pipeline
that reuses the quality and security controls already established in Phase 4.
The learning objective is Jenkins orchestration: agent preparation, fail-fast
stages, credentials, persistent tool data, and results published in the Jenkins
UI. This phase does not redesign the existing Gradle quality gates.

## 2. Existing baseline (not reimplemented in this phase)

The repository already provides:

- the Gradle Checkstyle plugin, the project ruleset and reviewed suppressions;
- the OWASP Dependency-Check Gradle plugin `12.2.2`, a blocking CVSS threshold
  of `7.0`, runtime and build-tooling scan tasks, report formats, reviewed
  suppressions, and `NVD_API_KEY` lookup; the key already exists as a GitHub
  Actions repository secret but is not accessible to Jenkins;
- the shared `.gitleaks.toml` policy used by GitHub Actions;
- the Phase 14 Multibranch Pipeline, SCM checkout support, `build-test` agent
  routing, GitHub webhook trigger, and commit-status publication; and
- the JCasC-managed Jenkins Credentials Store.

Phase 15 must consume this baseline rather than create a second set of rules,
thresholds, or suppressions for Jenkins.

## 3. Scope

In scope:

- preparing the Build/Test Agent for the existing Gradle, Testcontainers, and
  Gitleaks workloads;
- adding the Jenkins plugins required to publish JUnit and Checkstyle results;
- replacing the placeholder `Jenkinsfile` with explicit Checkout, Build, Test,
  Checkstyle, runtime dependency scan, build dependency scan, and Gitleaks
  stages;
- publishing test results, analysis reports, and security reports in Jenkins;
- persisting both the Gradle user home and the Dependency-Check vulnerability
  database across builds, and registering the existing NVD API key separately
  in Jenkins credentials; and
- demonstrating both a clean run and controlled gate failures on temporary
  verification branches.

Out of scope:

- changing the Phase 4 Checkstyle rules, CVSS threshold, Dependency-Check
  suppressions, or Gitleaks policy unless a genuine defect is discovered;
- changing the GitHub Actions CI implementation;
- Docker image build and Trivy container/IaC scanning (Phase 16, on the Docker
  Agent);
- deployment or GCP authentication logic (Phase 17); and
- replacing Testcontainers with a Jenkins-specific database service.

## 4. Functional requirements

1. The pipeline must run on the existing `build-test` label, disable Declarative
   Pipeline's implicit checkout, and expose one explicit `Checkout` stage using
   `checkout scm`. This must retrieve the branch commit or the synthetic
   `pr-merge` revision selected by the Phase 14 Multibranch job without a second
   checkout.
2. The `Build` stage must run `./gradlew clean assemble --no-daemon`, compiling
   and packaging the application without running the later verification tasks
   prematurely.
3. The Build/Test Agent must be able to reach a Docker daemon solely so the
   existing PostgreSQL Testcontainers integration tests can start their
   ephemeral database. The `Test` stage must run `./gradlew test --no-daemon`,
   publish `build/test-results/test/*.xml` through Jenkins' JUnit support even
   on failure, and stop all later stages when a test fails.
4. The `Checkstyle` stage must run the existing `checkstyleMain` and
   `checkstyleTest` tasks. Checkstyle XML output must be enabled for the Jenkins
   parser; `recordIssues` from Warnings Next Generation (or an equivalent
   Jenkins-native publisher) must expose findings in the build UI, while the
   existing HTML/SARIF reports remain available as artifacts. A Checkstyle
   violation remains a failed gate, matching GitHub Actions and Phase 4.
5. The `Runtime Dependency Check` stage must invoke the existing
   `dependencyCheckAnalyze` task and always archive its generated reports. The
   existing `failBuildOnCVSS = 7.0` policy remains the source of the exit status.
6. The `Build Dependency Check` stage must inventory the Gradle build
   environment and invoke the existing `dependencyCheckBuildEnvironment` task,
   archiving the build-tooling inventory and reports. Its existing CVSS `7.0`
   policy must remain unchanged. Jenkins must reuse the shared reviewed
   suppression file; a newly demonstrated identification defect may be corrected
   there through a scoped, owned, and expiring rule rather than a Jenkins-only
   exception.
7. Dependency-Check data must live in a named Compose volume outside an
   individual branch workspace so NVD downloads survive job and agent-container
   recreation. Gradle must keep the repository-local directory as the GitHub
   Actions/local fallback while accepting the Jenkins cache path through an
   environment variable.
8. The Gradle user home must live in a second named Compose volume mounted on
   the Build/Test Agent. This volume caches the Wrapper distribution, resolved
   dependencies, and reusable Gradle data across agent recreation; it does not
   replace the repository-owned Wrapper or decide the Gradle version.
9. The existing NVD API key must be registered as a Jenkins secret-text
   credential because Jenkins cannot read GitHub Actions repository secrets. It
   must be injected into the scan stages through `withCredentials` and must not
   appear in the `Jenkinsfile`, image, console output, or committed environment
   files. This reuses the existing external key; it does not create a second NVD
   key.
10. A pinned Gitleaks CLI must be installed in the Build/Test Agent image. The
   `Gitleaks` stage must scan the checked-out Git history with the existing
   `.gitleaks.toml`, produce an archivable redacted machine-readable report, and
   fail the build when a likely committed secret is detected. The archived
   report must never contain the detected secret value.
11. The Controller image must explicitly install the Jenkins plugins used by
    the pipeline for JUnit publication and Checkstyle issue recording. Plugin
    configuration must remain reproducible through the versioned Controller
    image rather than manual Plugin Manager changes.
12. Stages must execute sequentially and fail fast. Compilation, test,
    Checkstyle, Dependency-Check, or Gitleaks failure must mark the run as
    `FAILURE`; `post` publication steps may still run to preserve diagnostic
    evidence.

## 5. Non-functional requirements

- CI gate: Jenkins must reject the same compilation, test, code-quality,
  high/critical dependency, and secret-leak failures already rejected by GitHub
  Actions.
- Security: Docker-daemon access on the Build/Test Agent is a new privilege
  boundary required by Testcontainers. The pipeline must not use that access to
  build or publish application images; those operations remain isolated on the
  Docker Agent in Phase 16.
- Security: tool credentials must come from the JCasC-managed Credentials Store
  and be bound only around the command that consumes them.
- Security: Gitleaks output retained by Jenkins must use redaction so the
  diagnostic artifact cannot become a second location containing a leaked
  value.
- Reproducibility: Gitleaks and Jenkins plugin versions must be pinned, while
  the existing repository-owned quality configurations remain shared by both CI
  platforms.
- Observability: stage results, JUnit results, Checkstyle issues, and archived
  Dependency-Check/Gitleaks reports must be reachable from the classic Jenkins
  build page without requiring Blue Ocean or an external dashboard.

## 6. Acceptance criteria

- [x] a webhook-triggered branch or PR run executes the explicit Checkout,
      Build, Test, Checkstyle, Runtime Dependency Check, Build Dependency Check,
      and Gitleaks stages on the Build/Test Agent
- [x] the Test stage successfully starts PostgreSQL 16 through Testcontainers
      and publishes JUnit results in Jenkins
- [x] a deliberately failing test on a temporary verification branch marks the
      build as failed and prevents all later stages from running
- [x] Checkstyle findings are visible through the Jenkins recorded-issues view,
      and its existing Gradle gate remains blocking
- [x] both Dependency-Check tasks use the persistent NVD data directory,
      enforce the existing CVSS `7.0` threshold, and archive their reports even
      when a scan fails
- [x] Gitleaks scans Git history with the shared configuration, archives its
      report, and a synthetic secret committed only to a temporary verification
      branch causes the expected failed stage
- [x] a clean run completes successfully and publishes the Jenkins commit status
      to GitHub
- [x] recreating the Build/Test Agent without removing named volumes preserves
      both the Gradle and Dependency-Check caches, and a later build reuses them

## 7. Deliverables

- workflow: an extended root `Jenkinsfile` containing the complete CI stage
  sequence and report publication behavior;
- Jenkins infrastructure: Build/Test Agent tooling and Testcontainers access,
  explicit Controller reporting plugins, persistent Gradle and Dependency-Check
  storage, and JCasC-managed wiring for the existing NVD API key;
- minimal Gradle adjustment: only the portable Dependency-Check data-directory
  override and explicit Checkstyle XML output if required by Jenkins reporting;
- documentation: updated `docs/jenkins.md`, Phase 15 textual verification
  evidence, and an ADR recording Jenkins-specific execution and security
  decisions.

The existing Checkstyle rules, Dependency-Check policies/suppressions, and
`.gitleaks.toml` are reused deliverables from Phase 4, not new Phase 15 files.

## 8. Evidence

- a clean Jenkins run showing every CI stage and the `build-test-agent` node;
- Jenkins JUnit and recorded-issues pages plus archived Checkstyle,
  Dependency-Check, build-dependency, and Gitleaks reports;
- a controlled failing-test run showing fail-fast stage behavior;
- a controlled synthetic-secret run showing the Gitleaks gate and failed commit
  status; and
- before/after cache evidence showing that Gradle and Dependency-Check data
  survive Build/Test Agent recreation.

Evidence is recorded textually in the repository; screenshots are optional and
not required for phase completion.

## 9. Risks and mitigations

- risk: Docker socket access gives the Build/Test Agent control over the host
  Docker daemon, even though the intended consumer is Testcontainers.
  mitigation: keep the agent private and label-restricted, run only trusted
  repository code, document the boundary, and reserve image build/push commands
  for the Docker Agent.
- risk: rebuilding an agent or using a different Multibranch workspace could
  repeatedly download the Gradle distribution, dependencies, and NVD database,
  making builds slow and potentially encountering NVD rate limits.
  mitigation: use separate named Gradle and Dependency-Check volumes and inject
  the existing NVD API key from Jenkins credentials.
- risk: a sequential fail-fast pipeline does not report later gate results after
  an earlier failure.
  mitigation: publish diagnostics in `post` blocks, fix the first blocking
  failure, and rerun; this preserves the explicit stage order required by the
  learning plan.
- risk: manually installed reporting plugins or an unpinned Gitleaks binary
  would make a recreated Controller/Agent behave differently.
  mitigation: pin them in the versioned Dockerfiles/plugin list and validate a
  rebuild from those definitions.
- risk: temporary negative-test branches could retain intentionally broken code
  or synthetic secrets.
  mitigation: use unmistakably fake values, never real credentials, delete the
  branches after evidence is recorded, and do not merge them.

## 10. Definition of done (phase)

- [x] implementation complete (agent capabilities, reporting plugins, cache,
      credentials, and all Jenkins CI stages are version controlled)
- [x] clean and controlled-failure pipeline runs behave as specified
- [x] Jenkins reports and archived artifacts are accessible from the build page
- [x] documentation and textual verification evidence are updated
- [x] Jenkins-specific decisions and the expanded Docker trust boundary are
      recorded in `docs/decisions.md`
