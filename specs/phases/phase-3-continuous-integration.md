# Spec: Phase 3 - Continuous Integration (GitHub Actions)

## 1. Goal

Ensure that every change pushed to the repository is automatically verified through a GitHub Actions pipeline, extending the baseline CI workflow from Phase 0 into a real quality gate that builds and tests the application on every push. This is the first of two CI/CD implementations planned for the project: a GitHub-native one (this phase) and an independent one based on Jenkins (Phase 14 onwards), sharing the same application, artifact, and cloud infrastructure.

## 2. Scope

In scope:

- GitHub Actions workflow covering checkout, build, unit tests, and integration tests
- `./gradlew clean build` as the core pipeline command
- pipeline triggers (push and pull request to the main branch)
- Gradle dependency caching to speed up pipeline runs
- integration tests running against a real PostgreSQL instance in CI (e.g. via Testcontainers or a service container)
- a quality gate that fails the pipeline on build or test failure

Out of scope:

- static analysis, dependency scanning, and secret scanning (Phase 4)
- Docker image build and push in CI (Phase 5)
- deployment automation (Phase 6+)
- Terraform validation in CI (Phase 8)
- Jenkins setup, webhook integration, `Jenkinsfile`, and the Jenkins-based CI/CD pipeline (Phase 14-18) — Jenkins is a separate, independent pipeline implementation and is not configured, triggered, or extended as part of this spec

## 3. Functional requirements

1. The workflow must trigger on every push and pull request targeting the main branch.
2. The workflow must check out the repository code as its first step.
3. The workflow must run `./gradlew clean build`, which compiles the application, runs unit tests, runs integration tests, and assembles the artifact.
4. The workflow must provide a PostgreSQL instance available to integration tests, either through Testcontainers (Docker-in-Docker on the runner) or a GitHub Actions service container.
5. The workflow must cache Gradle dependencies between runs to reduce build time.
6. The workflow must fail (non-zero exit status) if compilation fails, if any unit test fails, or if any integration test fails.
7. The workflow must report a clear pass/fail status visible on the pull request and on the commit history.

## 4. Non-functional requirements

- CI gate: a commit must not be considered valid if the project does not compile, if unit tests fail, or if integration tests fail; the pipeline status must reflect this directly on GitHub.
- Security: no credentials for the CI-provisioned PostgreSQL instance should be reused for anything beyond the pipeline run; test database credentials must be simple, non-sensitive values scoped to CI only.
- Observability: the workflow must produce readable logs for each step (checkout, build, test) so failures can be diagnosed directly from the GitHub Actions run without needing to reproduce locally.

## 5. Acceptance criteria

- [ ] workflow triggers automatically on push and pull request to the main branch
- [ ] `./gradlew clean build` runs successfully in CI, including unit and integration tests
- [ ] integration tests in CI connect to a real PostgreSQL instance and pass
- [ ] Gradle dependency caching is configured and measurably reduces run time on subsequent runs
- [ ] a deliberately broken commit (failing test or compilation error) causes the pipeline to fail and is visibly marked as failed on GitHub
- [ ] pipeline status is visible on pull requests before merging

## 6. Deliverables

- code: no application code changes expected in this phase
- workflow: updated `.github/workflows/ci.yml` with build, test, caching, and PostgreSQL service/Testcontainers support
- documentation: updated `README.md` section describing the GitHub Actions CI pipeline and how to reproduce it locally, noting that Jenkins is introduced later as a separate, alternative pipeline implementation

## 7. Evidence

- link to a successful CI run showing checkout, build, and test steps passing
- link to a CI run on a deliberately failing commit, showing the pipeline correctly failing
- screenshot of pipeline status displayed on a pull request
- before/after timing comparison showing the effect of Gradle caching

## 8. Risks and mitigations

- risk: running integration tests with Testcontainers on GitHub-hosted runners could be slow or fail due to Docker-in-Docker limitations.
  mitigation: verify Testcontainers compatibility with the chosen runner image early, and fall back to a GitHub Actions service container for PostgreSQL if needed.
- risk: without dependency caching, every pipeline run could take significantly longer, discouraging frequent commits.
  mitigation: configure Gradle build cache and dependency caching explicitly in the workflow, and verify cache hits on subsequent runs.
- risk: a pipeline that passes even when tests are skipped or silently ignored would give a false sense of safety.
  mitigation: verify the quality gate by intentionally introducing a failing test and confirming the pipeline reports failure correctly.
- risk: building this pipeline without keeping the future Jenkins implementation in mind could lead to two CI/CD pipelines with inconsistent stages, making them hard to compare or maintain.
  mitigation: design the GitHub Actions pipeline stages (build, test, and later security scan, Docker build, registry push) so they can be conceptually mirrored in the `Jenkinsfile` introduced in Phase 16, without duplicating logic in incompatible ways.

## 9. Definition of done (phase)

- [ ] implementation complete (CI workflow with build, test, caching, and database support for integration tests)
- [ ] tests pass (`./gradlew clean build` green on CI for a valid commit, and correctly red for a broken one)
- [ ] documentation updated (README section describing the CI pipeline, scoped explicitly to GitHub Actions)
- [ ] decisions recorded (if needed, e.g. Testcontainers vs. service container choice) in `docs/decisions.md` or equivalent
