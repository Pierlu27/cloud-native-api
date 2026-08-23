# Spec: Phase 0 - Preparation

## 1. Goal

Set up the repository, toolchain, and documentation structure needed to start the implementation phases of the Cloud-Native CI/CD Platform, ensuring a reproducible starting point to progressively build the application, containerization, CI/CD, and infrastructure on Google Cloud Platform.

## 2. Scope

In scope:

- bootstrap Spring Boot/Gradle project
- `docs/`, `specs/`, `terraform/`, `.github/workflows/` folder structure
- baseline CI workflow
- initial documentation (README, spec template, first architecture draft)
- local environment setup (Java, Docker, Git)
- preliminary check of GCP toolchain availability (gcloud CLI, Terraform), without provisioning any cloud resources

Out of scope:

- full Job API implementation (Phase 1)
- application containerization (Phase 2)
- full CI pipeline with integration tests, security scanning, quality gates (Phase 3/4)
- creating or configuring an actual GCP project and its resources
- deployment to GCP (Phase 6+)
- defining Terraform modules (Phase 8)

## 3. Functional requirements

1. The repository must contain a Spring Boot project bootstrapped with Gradle, using the standard `src/main/java` and `src/test/java` layout.
2. The application must expose at least one minimal endpoint (e.g. a health check) to verify that it starts correctly.
3. The repository must include the `docs/`, `specs/`, `terraform/`, and `.github/workflows/` folders, even if initially empty or containing only placeholder files.
4. A reusable spec template (`SPEC_TEMPLATE.md`) must exist and follow the format adopted for all subsequent specs in the project.
5. A minimal GitHub Actions workflow must exist that checks out the code and runs build/test on every push.
6. An initial `README.md` must exist describing the project goal, tech stack, and local setup instructions.
7. A `.gitignore` file must exist, consistent with the Java/Gradle/Docker stack.

## 4. Non-functional requirements

- CI gate: the CI workflow must complete with a `success` status on the main branch before this phase is considered complete.
- Security: no secrets, credentials, or sensitive configuration files must be present in the repository at this stage, since no real GCP integration is expected yet.
- Observability: not applicable at this stage; introduced starting from Phase 11.

## 5. Acceptance criteria

- [x] repository initialized with a consistent structure (`src/`, `docs/`, `specs/`, `terraform/`, `.github/workflows/`)
- [x] `./gradlew test` runs successfully locally
- [x] spec template available and used as the reference for subsequent specs
- [x] initial documents present in `docs/` (at least a README with local setup instructions)
- [x] baseline CI workflow present in `.github/workflows/` and run successfully at least once on GitHub Actions
- [x] local environment verified: Java, Docker, and Git working; gcloud CLI and Terraform installed (no need to authenticate against a real GCP project at this stage)

## 6. Deliverables

- code: bootstrapped Spring Boot/Gradle project with a minimal health check endpoint
- workflow: `.github/workflows/ci.yml` file with checkout, build, and test steps
- documentation: `README.md`, `SPEC_TEMPLATE.md`, first spec (`specs/phases/phase-00-preparation.md`)

## 7. Evidence

Retrospective completion record (2026-08-21):

- the repository contains the required Spring Boot/Gradle sources and the
  `docs/`, `specs/`, `terraform/`, and `.github/workflows/` structure;
- `specs/SPEC_TEMPLATE.md` exists and all subsequent phase specs follow its
  structure;
- `README.md`, `docs/architecture.md`, and `docs/local-toolchain-setup.md`
  provide the initial project and local setup documentation;
- commit `0e6ed7020343342c3298018c4959a537085d2cfb` introduced the completed
  Phase 0 setup and baseline workflow. Its own GitHub Actions run failed, so it
  is not used as successful CI evidence. The same baseline was subsequently
  exercised successfully by the first Phase 1 push in
  [GitHub Actions run 31944062868](https://github.com/Pierlu27/cloud-native-api/actions/runs/31944062868);
- the stronger Phase 1 test suite later passed locally and in CI, as recorded
  by the completed Phase 1 acceptance checklist, superseding the minimal
  Phase 0 test evidence;
- Java, Git, Docker, gcloud CLI, and Terraform executables are installed. A
  2026-08-21 recheck found Git `2.49.0.windows.1`, Docker client `29.5.3`,
  Google Cloud SDK `581.0.0`, and a Terraform executable installed through
  WinGet. Gradle also resolved the Java 25 toolchain required by the current
  build;
- the 2026-08-21 local test recheck compiled the current application but could
  not complete two Testcontainers-based tests because the Docker daemon was
  not running. This is a current runtime prerequisite, not a missing Phase 0
  deliverable.

## 8. Risks and mitigations

- risk: the folder structure chosen at this stage may turn out to be inadequate once Terraform modules or more complex CI steps are introduced.
  mitigation: keep the structure simple and revisable, documenting any structural change in later specs instead of locking in premature decisions.
- risk: not having a real GCP project at this stage may delay verifying that the gcloud CLI and credentials are set up correctly.
  mitigation: limit this phase's goal to installing/checking the tools locally, deferring authentication and resource creation to later phases (Phase 6+).
- risk: an overly minimal CI workflow could give a false sense of coverage (build passing without real test depth).
  mitigation: Phase 3 will extend the workflow with integration tests and an explicit quality gate; a build/test-only CI is acceptable at this stage.

## 9. Definition of done (phase)

- [x] implementation complete (repository bootstrap, folder structure, baseline CI, initial documentation)
- [x] tests pass (`./gradlew test` green both locally and on CI)
- [x] documentation updated (README and spec template present and usable)
- [x] decisions recorded (if needed, e.g. folder structure choice) in `docs/decisions.md` or equivalent
