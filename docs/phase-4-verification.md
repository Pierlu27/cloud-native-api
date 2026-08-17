# Phase 4 verification evidence

## Local verification

Run the static-analysis and dependency-scan commands:

```bash
./gradlew checkstyleMain checkstyleTest --no-daemon
./gradlew dependencyCheckAnalyze --no-daemon
docker run --rm -v "${PWD}:/repo" ghcr.io/gitleaks/gitleaks:v8.24.2 git --config /repo/.gitleaks.toml /repo
```

The dependency scan may take longer on its first run while downloading NVD data.
Set `NVD_API_KEY` locally only when needed; do not commit it.

The Gitleaks command completed successfully against the repository history with
no leaks found.

## GitHub Actions evidence to record

- a successful pull-request run showing `Dependency scan`, `Secret scan`, and
  `Static analysis` alongside `Build and test`;
- a deliberately introduced fake secret causing `Secret scan` to fail, followed
  by a revert and a successful run;
- a deliberately introduced high/critical vulnerable test dependency causing
  `Dependency scan` to fail, followed by a revert and a successful run;
- a screenshot of the pull-request checks or annotations;
- an example of a narrowly scoped false-positive exception and its review link.

Deliberately unsafe test changes must only be pushed to a dedicated verification
branch and reverted immediately after collecting evidence.
