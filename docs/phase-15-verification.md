# Phase 15 Jenkins CI verification

Verification window: 2026-09-01 through 2026-09-03.

Phase 15 is complete. Evidence is recorded textually; screenshots are optional
and were not required to establish the results below.

## Reproducible CI runtime

Compose exposes three persistent Jenkins data stores:

```text
jenkins_home
gradle_cache
dependency_check_data
```

The project-owned Controller image installed the pinned JUnit and Warnings Next
Generation plugins. The Build/Test Agent image copied Gitleaks `v8.30.1` from
its official image and ran project commands as the unprivileged `jenkins` user.
The agent received supplementary group `0` only to open Docker Desktop's
`root:root` socket for Testcontainers; it did not contain the Docker CLI.

JCasC registered credential IDs `github-cloud-native-api` and `nvd-api-key`
without exposing either value. Both Dependency-Check stages successfully used
the NVD key through a command-scoped `withCredentials` binding.

## Clean webhook-triggered pipeline

The GitHub webhook triggered branch build 2 for commit `d25f481` on
`feat/phase-15-jenkins-ci`. Jenkins executed every stage sequentially on
`build-test-agent`:

```text
Checkout                  PASS
Build                     PASS
Test                      PASS - 18 tests, 0 failures, 0 skipped
Checkstyle                PASS - 0 recorded issues
Runtime Dependency Check  PASS
Build Dependency Check    PASS - 0 vulnerabilities
Gitleaks                  PASS - 0 findings
```

The tests started the existing `postgres:16-alpine` Testcontainers database.
JUnit published all 18 results, Warnings Next Generation parsed both Checkstyle
XML files, and Jenkins archived 12 Checkstyle, runtime/build Dependency-Check,
build-inventory, and Gitleaks artifacts. The runtime report retained one medium
DOMPurify CVE represented in both Swagger UI bundles; it remained below the
unchanged blocking threshold of CVSS `7.0`.

Jenkins published the final GitHub status:

```text
continuous-integration/jenkins/branch = success
This commit looks good
```

## Dependency findings reviewed during verification

The first complete branch run correctly failed at Runtime Dependency Check when
Spring Boot `4.1.0` resolved vulnerable Spring Framework `7.0.8` modules. Main
already contained Dependabot's Spring Boot `4.1.1` update, but the feature branch
did not yet contain that commit and the scan-only `buildPluginClasspath` mirror
still named `4.1.0`. Merging main and aligning the mirror resolved Spring
Framework `7.0.9`; application tests and the runtime scan then passed.

The build-tool scan also exposed two incorrect product identities:

```text
dependency-management-plugin -> Spring Framework
spring-boot-loader-tools      -> Spring Tools IDE extensions
```

These were genuine Dependency-Check CPE matching defects, not accepted product
vulnerabilities. The shared build suppression file now pairs the exact Maven
Package URL with only the incorrect CPE identity and retains its owner and
`2026-09-19` review expiry. It does not suppress the valid `spring_boot` identity
or change the CVSS gate. The corrected build scan reported zero vulnerabilities.

## Controlled JUnit failure

Temporary branch `verify/phase-15-test-failure`, commit `70a64f9`, added one
unmistakably intentional failing JUnit test. Its Jenkins build produced:

```text
Checkout  PASS
Build     PASS
Test      FAILURE - 19 tests, 1 failure
remaining stages skipped due to earlier failure(s)
```

The Test stage's `post` block still published the JUnit result, and GitHub
received `This commit cannot be built`. The branch and its worktree were deleted
without merge after the evidence was collected.

## Controlled Gitleaks failure and redaction

Temporary branch `verify/phase-15-gitleaks-failure`, commit `2bf2630`, committed
a non-functional high-entropy value with generic API-key context. Every earlier
stage passed before Gitleaks produced:

```text
RuleID:  generic-api-key
Finding: PHASE15_VERIFICATION_API_KEY="REDACTED"
leaks found: 1
```

The archived JSON contained one finding and the word `REDACTED`; it did not
contain the synthetic value. Jenkins and GitHub marked the run failed. The
remote branch, local branch, linked worktree, and standalone test clone were all
deleted without merge.

## Real cache persistence after agent recreation

Before recreation, the named volumes contained real tool data:

```text
Gradle cache:           779,379,954 bytes
Gradle distributions:  9.7.0 and 9.7.1
Dependency-Check data: 249,130,536 bytes
odc.mv.db:              248,496,128 bytes
```

`docker compose up -d --force-recreate --no-deps build-test-agent` replaced
container `429d5f62991a...` with `15e04cd9327b...`. The same named volumes,
byte counts, Wrapper distributions, and NVD database remained present, and the
new container reconnected to the JCasC node as online and idle.

Manual branch build 3 then completed successfully in 116 seconds. Its log did
not contain a Gradle distribution download; Runtime Dependency Check completed
in 22 seconds and Build Dependency Check in 15 seconds. This demonstrates that
the recreated agent reused both persistent caches rather than repopulating them.

## Gradle Wrapper line-ending normalization

After main was merged, `gradlew.bat` appeared modified even though its raw bytes
matched the committed blob. Dependabot commit `22bc5dc` had stored the batch
file with CRLF bytes, while `.gitattributes` requires text normalization in Git
and CRLF only in the checkout. Git therefore compared the non-normalized index
blob with the normalized working-tree content and reported a permanent change.

`git add --renormalize gradlew.bat` restored the intended state:

```text
i/lf    w/crlf  attr/text eol=crlf
```

The logical diff ignoring carriage returns was empty. Commit `fd38cfc` changes
only Git's stored line endings; Windows continues to receive a CRLF batch file.

## Result

The clean run, both controlled failure gates, report publication, GitHub commit
statuses, Testcontainers execution, secret redaction, and real cache reuse were
all observed. No temporary verification branch or synthetic secret was merged.
