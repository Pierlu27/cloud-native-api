# Spec: Phase 4 - Code Quality & Security

## 1. Goal

Extend the GitHub Actions pipeline from Phase 3 with automated code quality and security checks, so that dependency vulnerabilities, leaked secrets, and static analysis issues are caught before a commit is considered valid.

## 2. Scope

In scope:

- dependency vulnerability scanning (e.g. Dependabot alerts and/or a dedicated scanning step)
- secret detection scanning across the repository and commit history
- static analysis / code quality checks integrated into the pipeline
- extending the existing quality gate to fail on high-severity findings

Out of scope:

- Docker image scanning (Phase 5, since no image is built yet at this stage)
- Jenkins-side security scanning (Phase 14-18, handled separately for the Jenkins pipeline)
- Secret Manager and runtime IAM setup on GCP (out of scope here and subsequently completed in Phase 8)
- fixing every possible low-severity finding across all dependencies (only high/critical findings are required to block the pipeline; lower-severity findings are tracked but not necessarily blocking)

## 3. Functional requirements

1. The pipeline must run a dependency vulnerability scan (e.g. via Dependabot or an equivalent Gradle-compatible scanner) on every push and pull request.
2. The pipeline must run a secret detection step that scans the diff (and ideally the full history) for accidentally committed credentials, keys, or tokens.
3. The pipeline must run a static analysis step (e.g. a linter or code quality tool suited for Java/Gradle projects) and report findings.
4. The pipeline must fail if the dependency scan reports a high or critical severity vulnerability with no accepted exception.
5. The pipeline must fail if the secret detection step finds a likely secret in the scanned diff.
6. Findings from static analysis, dependency scanning, and secret detection must be visible in the CI run output or as pull request annotations, not just as a pass/fail signal.
7. A documented process must exist for handling false positives (e.g. suppressing or accepting a specific finding with a recorded justification).

## 4. Non-functional requirements

- CI gate: a commit must not be considered valid if a high/critical dependency vulnerability or a detected secret is found, in addition to the build/test gate already enforced in Phase 3.
- Security: scanning tools must not require exposing any real credentials in CI; any tokens needed by the scanners themselves must be handled through GitHub Actions secrets, not hardcoded in the workflow file.
- Observability: scan results must be readable directly from the GitHub Actions run (logs, summary, or annotations), without requiring a separate dashboard to understand why a build failed.

## 5. Acceptance criteria

- [x] dependency vulnerability scan runs automatically on every push/pull request and reports findings
- [x] secret detection step runs automatically and correctly flags a deliberately introduced fake secret in a test commit
- [x] static analysis step runs and produces a visible report (console output or PR annotations)
- [x] a deliberately introduced high/critical vulnerability (e.g. via a vulnerable test dependency) causes the pipeline to fail
- [x] a documented, working process exists for marking a specific finding as an accepted false positive without disabling the whole check
- [x] pipeline still passes cleanly on the current, clean codebase after these checks are added

## 6. Deliverables

- code: no application code changes expected in this phase, aside from potential fixes to findings surfaced by the new checks
- workflow: updated `.github/workflows/ci.yml` with dependency scanning, secret scanning, and static analysis steps added to the existing build/test job
- documentation: updated `docs/security.md` (or equivalent) describing which tools are used, what triggers a pipeline failure, and how to handle false positives

## 7. Evidence

Completion status reviewed on 2026-08-21:

- [GitHub Actions run 32392965174](https://github.com/Pierlu27/cloud-native-api/actions/runs/32392965174)
  is a successful pull-request run of the current workflow;
- `.github/workflows/ci.yml` contains the blocking runtime dependency scan,
  build dependency scan, full-history Gitleaks scan, and Checkstyle jobs, with
  their reports uploaded as workflow artifacts where applicable;
- `docs/phase-4-verification.md` records the local scan results, dependency
  remediation, build dependency baseline, and reviewed exceptions;
- `docs/security.md` documents failure thresholds and the narrowly scoped
  exception process for Dependency-Check, Gitleaks, and Checkstyle;
- `config/dependency-check/build-suppressions.xml` provides concrete,
  time-bounded examples of reviewed exceptions instead of disabling the gate;
- the phase is considered complete based on the implemented blocking
  configuration, the documented thresholds, and successful execution of the
  clean pipeline. Links to historical runs containing deliberately introduced
  fake secrets or vulnerable dependencies were not preserved and those unsafe
  checks were not re-executed during the 2026-08-21 retrospective review.

## 8. Risks and mitigations

- risk: overly strict scanning rules could generate excessive false positives, causing the team to start ignoring pipeline failures altogether.
  mitigation: start with a conservative severity threshold (block only on high/critical) and document a clear false-positive exception process from day one.
- risk: secret detection tools scanning only the latest diff could miss secrets already committed earlier in the repository's history.
  mitigation: run at least one full-history secret scan when the check is first introduced, in addition to the ongoing diff-based scan on every push.
- risk: adding multiple new scanning steps could significantly increase pipeline run time.
  mitigation: run independent checks (dependency scan, secret scan, static analysis) as parallel jobs where the CI platform supports it, instead of chaining them sequentially.

## 9. Definition of done (phase)

- [x] implementation complete (dependency scanning, secret scanning, and static analysis integrated into the GitHub Actions pipeline)
- [x] tests pass (existing build/test gate from Phase 3 still green, new security/quality gates correctly blocking bad commits)
- [x] documentation updated (`docs/security.md` describing tools, thresholds, and the false-positive process)
- [x] decisions recorded (if needed, e.g. choice of scanning tools, severity threshold) in `docs/decisions.md` or equivalent
