# Phase 3 verification evidence

## Local verification

Run the CI-equivalent command with Docker available for Testcontainers:

```bash
./gradlew clean build --no-daemon
```

Expected result: compilation, unit tests, and PostgreSQL-backed integration tests pass.

## GitHub Actions evidence to record

After merging this workflow change or opening a pull request, add the following links
and timing observations to the related pull request or issue:

- a successful workflow run, showing checkout, Gradle setup/cache, and build/test steps;
- a run from a deliberately failing test or compilation error, showing a failed status;
- a screenshot of the workflow check visible on the pull request;
- first-run and subsequent-run durations, with the later run showing the Gradle cache
  restore in its logs.

The intentionally broken change must be reverted immediately after collecting evidence.
