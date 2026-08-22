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
now a blocking gate with a CVSS threshold of `7.0`, independently of the
runtime `dependency-scan` gate.

The scan uses the resolvable `buildPluginClasspath` configuration, which mirrors
the plugin marker dependencies declared by the Gradle `plugins` block. This is
necessary because an empty Dependency-Check report does not establish a clean
baseline. The populated baseline was reviewed and the High/Critical build gate
is now enabled; the approved, time-bounded exceptions below allow the current
clean build to pass without making the job informational.

The first populated baseline (2026-08-19) identified High/Critical findings in
the transitive Apache HttpComponents dependencies of the Spring Boot Gradle
plugin: `CVE-2026-54399` and `CVE-2026-54428` affect HttpCore `5.4.2`, and
`CVE-2026-71290` affects HttpClient `5.6.1`. The report also contains CPE
misidentifications for `dependency-management-plugin:1.1.7` and
`spring-boot-loader-tools:4.1.0`. The build gate remained informational while
these findings were reviewed. It became blocking after the narrowly scoped
exceptions below were approved with a CVE, owner, justification, and expiry
date.

The approved build exceptions below are in
`config/dependency-check/build-suppressions.xml`; all are owned by Pierluigi
and expire on 2026-09-19. They are scoped to one CVE and one exact Maven package
URL each.

| CVEs | Artifact | Justification |
| --- | --- | --- |
| CVE-2016-9878, CVE-2018-11040, CVE-2018-1270, CVE-2022-22965, CVE-2024-22259 | `dependency-management-plugin:1.1.7` | Reviewed CPE false positives for Spring Framework. |
| CVE-2022-31691 | `spring-boot-loader-tools:4.1.0` | Reviewed CPE false positive; the advisory concerns Spring Tools IDE extensions. |
| CVE-2026-54399, CVE-2026-54428 | `httpcore5:5.4.2`, `httpcore5-h2:5.4.2` | Transitive from Spring Boot Gradle Plugin; no supported 4.1.x remediation is available. |
| CVE-2026-71290 | `httpclient5:5.6.1` | Transitive from Spring Boot Gradle Plugin; no supported 4.1.x remediation is available. |

On 2026-08-19, the Gradle Wrapper was updated from `9.5.1` to `9.7.0` and
verified with `./gradlew clean build --no-daemon`. Dependabot is enabled for
both `gradle` and `github-actions` updates, so new build-tooling releases are
proposed in dedicated pull requests.

Use this inventory as the baseline for updating build tooling one component at a
time: Spring Boot Gradle plugin, OWASP Dependency-Check, Dependency Management,
the Gradle Wrapper, and GitHub Actions. Any temporary exception introduced in a
blocking gate must name the CVE, owner, justification, and expiry date.

## GitHub Actions evidence status

The current clean pipeline is demonstrated by
[GitHub Actions run 32392965174](https://github.com/Pierlu27/cloud-native-api/actions/runs/32392965174),
which includes `Build and test`, `Dependency scan`, `Secret scan`, and
`Static analysis`. The workflow definitions, blocking thresholds, generated
reports, and time-bounded exceptions provide reproducible evidence of the gate
behavior.

The original links for deliberately introduced fake-secret and vulnerable-test
commits were not retained. Those unsafe changes were reverted and were not
recreated merely to manufacture retrospective evidence. Any future destructive
gate test must use a dedicated verification branch and be reverted immediately.
