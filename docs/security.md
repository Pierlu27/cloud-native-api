# Security Controls

## CI quality and security gates

Every push to `develop` or `main` and every pull request targeting either branch
runs the applicable GitHub Actions validation jobs. A pull request is ready to
merge only when all required jobs pass.

| Job | Tool | Result | Blocking policy |
| --- | --- | --- | --- |
| Build and test | Gradle + Testcontainers | Compilation, unit tests, and PostgreSQL-backed integration tests | Any failure blocks the pipeline |
| Dependency scan | OWASP Dependency-Check | HTML, JSON, and SARIF reports for the API runtime classpath | CVSS 7.0 or higher blocks the pipeline |
| Secret scan | Gitleaks | Full Git history scan, CI summary, and pull-request comments for detected leaks | Any likely secret blocks the pipeline |
| Static analysis | Checkstyle | HTML and SARIF reports for main and test sources | Any configured rule violation blocks the pipeline |

Dependency-Check uses the NVD vulnerability feed. The optional `NVD_API_KEY`
repository secret reduces NVD API throttling; it is passed only as a GitHub
Actions secret and is never stored in the workflow or source code. The first
scan can be slower while vulnerability data is downloaded; later runs reuse
the dedicated Dependency-Check cache.

The scan is intentionally limited to Gradle's `runtimeClasspath`, which maps
to dependencies packaged with the API. `skipTestGroups` is disabled because
Spring Boot makes that configuration inherit development/test metadata; the
explicit runtime whitelist still excludes test-only and Gradle-plugin
dependencies. Build-tool dependencies are not part of the deployable artifact
and are updated through their own release cycles rather than treated as
application runtime findings.

Gitleaks scans the complete Git history because a secret committed and later
removed must still be treated as exposed. For repositories owned by a GitHub
organization, configure the `GITLEAKS_LICENSE` secret if required by the
Gitleaks GitHub Action; personal repositories do not require it.

Jenkins independently runs the Phase 15 build, test, Checkstyle,
Dependency-Check, and Gitleaks gates for discovered internal branches and
same-repository pull requests. Phase 16 adds two blocking Docker Agent stages:

| Stage | Trivy scope | Blocking policy | Retained reports |
|---|---|---|---|
| Trivy Image Scan | operating-system and language packages in the built application image | any `HIGH` or `CRITICAL` vulnerability | JSON and table text |
| Trivy IaC Scan | Terraform resources and their resolved non-secret example inputs | any `HIGH` or `CRITICAL` misconfiguration | JSON and table text |

The image command selects only the `vuln` scanner, so secrets and
misconfigurations do not silently expand that stage's gate. The IaC command
uses Trivy's versioned built-in checks, such as `GCP-0027` for unrestricted
firewall ingress. Both stages archive their available reports even when the
gate fails; every later stage, including image publishing, remains blocked.

## Publisher identities and trust boundaries

GitHub Actions and Jenkins publish to different packages inside the same
Artifact Registry repository:

| Publisher | Authentication | Allowed pipeline context | Package |
|---|---|---|---|
| GitHub Actions | short-lived OIDC through Workload Identity Federation | direct `main` push or manual `main` run after all gates | `cloud-native-api-prod` |
| local Jenkins | Base64-encoded long-lived service-account key | direct `develop` branch after all Jenkins gates | `cloud-native-api-dev` |

Each identity receives `roles/artifactregistry.writer` only on the application
repository. Artifact Registry does not apply that grant to only one package,
so the package names and pipeline conditions define operational ownership but
not a hard IAM boundary. Separate repositories would be required to enforce
package isolation at the authorization layer.

Terraform creates the Jenkins service account and repository binding but never
creates, reads, accepts, or outputs its private key. The Base64 payload is not
encrypted; it exists only in the ignored `jenkins/.env`, the Controller runtime
environment, and the JCasC-managed Credentials Store. The pipeline binds it
only around registry authentication, uses `--password-stdin`, and removes its
temporary Docker configuration through an exit trap.

The Jenkins Multibranch source does not discover fork pull requests. Internal
branch code is nevertheless trusted: it controls a `Jenkinsfile` that runs on
agents with Docker socket access and can refer to globally registered
credentials by ID. This local stack must not execute arbitrary public code or
serve as a shared production Jenkins installation.

The Jenkins key must be rotated after suspected exposure and removed when the
local publisher is retired. `docs/jenkins.md` contains the create, replace,
verify, disable, and delete procedure. Creating a temporary organization-policy
exception does not weaken the runtime key permissions, but that exception must
be removed immediately after key creation.

## Runtime secrets and rotation

Terraform manages the three Secret Manager containers, secret-scoped IAM
members, and Cloud Run references. Database payloads are added outside Terraform
so they do not enter configuration, plans, or state. The dedicated Cloud Run
runtime service account can read only those three secrets; it does not publish
or retrieve container images.

Datasource secrets are injected as environment variables pinned to numeric
versions. Cloud Run resolves each value before an instance starts, so running
instances do not observe a later payload automatically. A rotation must update
the numeric Terraform reference and deploy a new Cloud Run revision.

Security checks for every rotation:

1. never print or pass the payload through Terraform, CI, command history, or
   application logs;
2. review the plan before creating the new revision;
3. verify readiness and a database-backed operation on the new revision;
4. retain the previous secret version during the rollback window;
5. disable the previous version only after rollback no longer depends on it;
6. confirm the final Terraform plan is empty.

The complete operational sequence is in `docs/deployment.md`. Phase 9 image
delivery does not implicitly rotate secrets. Automated rotation remains out of
scope until a dedicated workflow can accept an approved numeric version and
preserve the same verification and rollback controls; this procedure defines
the current controlled manual cutover.

## False-positive exception process

Never suppress a finding until the value has been reviewed and confirmed not
to be a real secret or exploitable vulnerability. Record the reason, reviewer,
scope, and expiry date in the pull request that introduces the exception.

### Dependency-Check

1. Open the generated HTML report and use its suppression helper to create a
   rule for the exact dependency/CVE or CPE.
2. Add the generated rule to `config/dependency-check/suppressions.xml` with
   a `<notes>` explanation and an `until` date.
3. Link the review in the pull request and remove the rule when it expires.

Do not suppress findings by broad CVSS threshold, artifact wildcard, or an
unrelated dependency name.

### Gitleaks

1. Treat every detected value as real until confirmed otherwise; revoke and
   rotate real credentials instead of suppressing them.
2. For a confirmed false positive, add one exact, documented `[[allowlists]]`
   entry to `.gitleaks.toml`, scoped to the reviewed value or path.
3. Include the review link and expiry date in the allowlist description. Never
   allowlist an entire rule, repository, or arbitrary directory.

### Checkstyle

1. Fix the source code when practical.
2. If a rule is genuinely inapplicable, add a minimal file-and-rule suppression
   to `config/checkstyle/suppressions.xml` with the reason in the pull request.
3. Revisit suppressions when the affected code changes.

### Trivy

1. Classify a `HIGH` or `CRITICAL` result as a genuine vulnerability, an
   intentional design, or an identification defect before changing the gate.
2. Remediate a genuine image finding by updating the affected base image or
   package; remediate a genuine IaC finding by narrowing or removing the unsafe
   configuration.
3. Add no ignore entry without the exact rule/CVE, affected component, reviewed
   reason, owner, and expiry date. Never suppress an entire severity or scanner.
4. Keep controlled vulnerable-image and IaC fixtures on temporary branches,
   never apply or deploy them, and delete the branches and local images after
   the report proves the gate.

## Evidence

- GitHub Actions run links and generated reports: `docs/phase-4-verification.md`
- Architecture decisions: `docs/decisions.md`
- Phase 3 CI baseline evidence: `docs/phase-3-verification.md`
- Jenkins CI gate evidence: `docs/phase-15-verification.md`
- Jenkins container-security and publishing evidence:
  `docs/phase-16-verification.md`

Textual and reproducible evidence is the project default: commands, sanitized
outputs, test reports, workflow links, resource identifiers, and HTTP results
can be checked again without depending on a particular console layout.
Screenshots are retained only for Phase 3 because that phase explicitly studied
the GitHub Actions and pull-request interface: the visual quality-gate status
and cache presentation were themselves part of the learning evidence. They do
not establish a screenshot requirement for later phases.
