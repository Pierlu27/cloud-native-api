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

## Runtime dependency remediation (2026-08-18)

Spring Boot was already at the latest stable release in the requested 4.1.x
line (`4.1.0`). Its managed Tomcat version was nevertheless below the required
baseline, so the following targeted runtime changes were made:

| Component | Before | After |
| --- | --- | --- |
| `tomcat-embed-core` | `11.0.22` | `11.0.25` |
| `tomcat-embed-websocket` | `11.0.22` | `11.0.25` |
| PostgreSQL JDBC | version managed indirectly | `42.7.12` (direct `runtimeOnly`) |

`tomcat.version` is overridden through Spring Boot's dependency-management
property, keeping the embedded Tomcat modules aligned rather than overriding
individual artifacts.

The final commands completed successfully:

```bash
./gradlew clean build --no-daemon
./gradlew dependencyCheckAnalyze --no-daemon --rerun-tasks
```

Dependency-Check scans only `runtimeClasspath`. The final report contains zero
High/Critical findings. It retains five Medium findings for separate review,
without automatic suppressions: `CVE-2026-54515` (Jackson Databind),
`CVE-2026-49844` (two Log4j artifacts), and `GHSA-55q2-fjhq-7xh7` (two
DOMPurify bundles within Swagger UI).

The generated runtime reports are available locally at:

- `build/reports/dependency-check-report.html`
- `build/reports/dependency-check-report.json`
- `build/reports/dependency-check-report.sarif`

## Build dependency inventory

Build and CI dependencies are monitored separately from the deployable runtime.
The `Build dependency scan` CI check runs `./gradlew buildEnvironment` and
`./gradlew dependencyCheckBuildEnvironment`, publishing the resolved plugin
classpath and CVE reports as the `build-dependency-reports` artifact. It is
blocking for High/Critical findings: its CVSS threshold is `7.0`. It does not
alter the runtime `dependency-scan` gate.

On 2026-08-19, the Gradle Wrapper was updated from `9.5.1` to `9.7.0` and
verified with `./gradlew clean build --no-daemon`. Dependabot is enabled for
both `gradle` and `github-actions` updates, so new build-tooling releases are
proposed in dedicated pull requests.

Use this inventory as the baseline for updating build tooling one component at a
time: Spring Boot Gradle plugin, OWASP Dependency-Check, Dependency Management,
the Gradle Wrapper, and GitHub Actions. Any temporary exception introduced in a
blocking gate must name the CVE, owner, justification, and expiry date.

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
