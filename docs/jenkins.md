# Jenkins Local Stack

Phase 13 introduced Jenkins as a second, independent CI/CD learning platform.
Phase 14 makes the Controller configuration reproducible through Jenkins
Configuration as Code (JCasC), creates a GitHub Multibranch Pipeline through
Job DSL, and connects GitHub events to the local Controller through a temporary
Smee relay. Phase 15 implements the complete Jenkins CI sequence with reporting
plugins, Gitleaks, Testcontainers access, and persistent tool caches. The root
`Jenkinsfile` is now the revision-owned pipeline definition. Jenkins remains a
parallel learning path and does not yet replace GitHub Actions delivery.

## Architecture

The dedicated Compose stack contains four peer containers:

```text
Docker Desktop
├── controller
│   └── coordinates nodes, jobs, plugins, credentials, and build history
├── build-test-agent
│   └── executes Gradle, Gitleaks, and Testcontainers-backed test workloads
├── docker-agent
│   └── executes Docker CLI operations against Docker Desktop
└── webhook-relay
    └── forwards GitHub events from a temporary Smee channel to Jenkins
```

The agents are not nested inside the Controller. All four containers share the
private `cloud-native-api-jenkins-network`; Docker's internal DNS therefore
resolves the Compose service name `controller`.

| Caller | Controller address | Purpose |
|---|---|---|
| Browser on Windows | `http://localhost:8081` | Jenkins UI through the published host port |
| Agent container | `http://controller:8080` | Controller HTTP endpoint on the Compose network |
| Agent container | `controller:50000` | Fixed inbound-agent TCP connection |

`localhost` inside an agent refers to that agent container, not to the
Controller. Port `8081` exists only on the Windows host; containers communicate
with the Controller's internal port `8080`.

## Images and installed tooling

The project owns four reproducible images:

- `jenkins/controller/Dockerfile` pins the Jenkins LTS/JDK image and installs
  the versioned plugin list from `jenkins/controller/plugins.txt`;
- `jenkins/build-test-agent/Dockerfile` provides Java 25, Git, curl, and a
  pinned Gitleaks binary. Gradle is supplied by the repository's versioned
  wrapper rather than installed globally; and
- `jenkins/docker-agent/Dockerfile` combines the official inbound-agent runtime
  with a pinned Docker CLI, Buildx, Compose, Git, and curl; and
- `jenkins/webhook-relay/Dockerfile` installs the pinned official Smee client
  in a small Node image and runs it as the unprivileged `node` user.

The Controller plugins include Git, Pipeline, Credentials Binding, Docker
Pipeline, Configuration as Code, GitHub Branch Source, Job DSL, JUnit, and
Warnings Next Generation. JUnit publishes Gradle test XML; Warnings Next
Generation converts Checkstyle XML into navigable Jenkins issues. The Dark Theme
plugin is also installed for the local UI. JCasC applies the Controller
configuration automatically at startup; Job DSL creates the Multibranch parent
job from the `jobs` section of the same YAML file.

## Persistent and disposable state

The named volume `cloud-native-api-jenkins-home` is mounted at
`/var/jenkins_home`. It preserves users, plugins, node definitions, credentials,
jobs, build history, and Controller configuration across container recreation.

Build/Test Agent source workspaces remain disposable and reproducible from Git.
Two tool-data volumes survive agent recreation independently of those
workspaces:

| Volume | Agent path | Contents |
|---|---|---|
| `cloud-native-api-jenkins-gradle-cache` | `/home/jenkins/.gradle` | Gradle Wrapper distributions, resolved dependencies, and reusable Gradle data |
| `cloud-native-api-jenkins-dependency-check-data` | `/home/jenkins/.dependency-check-data` | NVD vulnerability data used by both Dependency-Check tasks |

The Gradle volume does not select the Gradle version; the repository-owned
Wrapper remains authoritative. The NVD volume replaces only Jenkins's default
workspace-local data directory. Local commands and GitHub Actions continue to
use the ignored project `.dependency-check-data` fallback.

Use `docker compose down` for a normal teardown. Do not add `-v` unless losing
the local Jenkins installation is intentional:

```text
docker compose down       -> removes containers/network, keeps all named volumes
docker compose down -v    -> also removes Controller, Gradle, and NVD volume data
```

## Current JCasC bootstrap

Copy `jenkins/agent-secrets.env.example` to the ignored `jenkins/.env` and
replace every placeholder. The local file supplies five different categories:

- administrator identity and password used by JCasC;
- GitHub username and fine-grained token used for discovery, checkout, and
  commit status publication;
- the existing NVD API key, registered separately as Jenkins secret-text
  credential `nvd-api-key` because Jenkins cannot read GitHub Actions secrets;
- the two Jenkins-generated inbound-agent secrets; and
- the temporary Smee channel URL used by the webhook relay.

Start the complete stack from the repository root:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml up -d --build
```

`CASC_STRICT_SECRET_RESOLUTION=true` makes startup fail when a variable
referenced by JCasC is missing instead of silently creating an incomplete or
unsafe configuration. `-Djenkins.install.runSetupWizard=false` skips the setup
wizard because JCasC creates the administrator and applies the system settings.

The Controller image contains `jenkins.yaml` at
`/usr/share/jenkins/ref/jenkins.yaml`. After changing the local YAML, rebuild
and recreate the Controller:

```bash
docker compose -f jenkins/docker-compose.yml build controller
docker compose -f jenkins/docker-compose.yml up -d controller
```

A reload without rebuilding only reapplies the copy already baked into the
current image. It is useful for reverting UI drift, but it does not copy a newly
edited local YAML into a running container.

On an empty Controller volume, JCasC recreates both node definitions without
manual UI setup. Jenkins generates new inbound secrets for that new Controller
state; obtain them from the two node pages and update only the ignored local
`.env` before starting the agent containers. Node identities are configuration
as code, while their connection secrets remain runtime state.

## Phase 15 continuous integration

The Build/Test Agent mounts the same Docker Desktop socket used by the Docker
Agent, but it does not install the Docker CLI. Testcontainers' Java Docker client
opens `/var/run/docker.sock` directly and asks the host daemon to create sibling
PostgreSQL and Ryuk containers. On Docker Desktop,
`TESTCONTAINERS_HOST_OVERRIDE=host.docker.internal` lets the agent reach the
random host ports published for PostgreSQL.

Compose adds supplementary group ID `0` because this local Docker Desktop socket
is `root:root` with group read/write permission. The agent process remains user
`jenkins`; group membership grants socket access without changing its UID.

`GRADLE_USER_HOME` points Gradle at its named volume.
`DEPENDENCY_CHECK_DATA_DIRECTORY` selects the separate NVD volume only in
Jenkins. JCasC resolves `JENKINS_NVD_API_KEY` from the ignored local environment
and creates credential ID `nvd-api-key`; the `Jenkinsfile` binds it as
`NVD_API_KEY` only around each Dependency-Check command.

The Declarative Pipeline disables its implicit checkout and executes these
stages in order on the `build-test` label:

| Stage | Command or responsibility |
|---|---|
| Checkout | `checkout scm` retrieves the Multibranch-selected branch or PR revision once |
| Build | `./gradlew clean assemble --no-daemon` compiles and packages without running later gates |
| Test | runs the Testcontainers-backed test suite and always publishes JUnit XML |
| Checkstyle | runs the existing Gradle gates, records XML through Warnings NG, and archives HTML/SARIF |
| Runtime Dependency Check | scans `runtimeClasspath` with the shared CVSS `7.0` policy and archives every report |
| Build Dependency Check | inventories and scans `buildPluginClasspath` with the shared policy and reviewed suppressions |
| Gitleaks | scans Git history with `.gitleaks.toml`, redacts values, and archives JSON |

Declarative stages fail fast: a failed command marks the run failed and skips
later stages. Each publisher is in `post { always { ... } }` where diagnostics
must survive the failure, so JUnit and security artifacts remain available.
The classic build page exposes tests, recorded issues, stage logs, and archived
reports without requiring Blue Ocean.

After changing agent tooling, plugins, or JCasC, rebuild and recreate the
affected services without removing volumes:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml build controller build-test-agent
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml up -d --force-recreate controller build-test-agent
```

Phase 15 verified a complete clean webhook run, controlled JUnit and Gitleaks
failures, redacted secret artifacts, and cache reuse after agent recreation.
See `docs/phase-15-verification.md` for the textual evidence.

## Historical Phase 13 manual bootstrap

The following procedure records the manual Phase 13 starting point. It is no
longer the current setup path because Phase 14 moves the administrator, system
settings, credentials, and node definitions into JCasC.

The Controller must exist before Jenkins can generate the two agent secrets.
From the repository root, start only the Controller using the tracked example
file to satisfy Compose interpolation without introducing a real credential:

```bash
docker compose \
  --env-file jenkins/agent-secrets.env.example \
  -f jenkins/docker-compose.yml \
  up -d --build controller
```

Open `http://localhost:8081` and complete the initial setup. The local bootstrap
password can be read directly from the container when required:

```bash
docker compose \
  --env-file jenkins/agent-secrets.env.example \
  -f jenkins/docker-compose.yml \
  exec controller cat /var/jenkins_home/secrets/initialAdminPassword
```

Configure the inbound-agent TCP port as fixed `50000`. This port is exposed
only to the private Compose network; it is not published to Windows.

Create two **Permanent Agent** node definitions in the Jenkins UI:

| Setting | Build/Test Agent | Docker Agent |
|---|---|---|
| Node name | `build-test-agent` | `docker-agent` |
| Executors | `1` | `1` |
| Remote root | `/home/jenkins/agent` | `/home/jenkins/agent` |
| Label | `build-test` | `docker` |
| Usage | only jobs matching the label | only jobs matching the label |
| Launch method | connect agent to Controller | connect agent to Controller |
| Availability | keep online as much as possible | keep online as much as possible |

Each node receives a unique inbound-agent secret. Copy
`jenkins/agent-secrets.env.example` to the ignored `jenkins/.env` and replace
both placeholders locally:

```dotenv
JENKINS_BUILD_AGENT_SECRET=replace-with-generated-build-agent-secret
JENKINS_DOCKER_AGENT_SECRET=replace-with-generated-docker-agent-secret
```

Never commit `jenkins/.env`, paste its values into documentation, or reuse one
node's secret for the other node. The repository-wide ignore rules exclude the
real `.env` file; the tracked example contains placeholders only.

Set the Jenkins **Built-In Node** executor count to `0` after both agents are
available. This keeps the Controller focused on orchestration and prevents
repository code from executing in the administrative container.

## Normal operation

After the node definitions and local secrets exist, start or recreate the whole
stack from the repository root:

```bash
docker compose \
  --env-file jenkins/.env \
  -f jenkins/docker-compose.yml \
  up -d --build
```

`--build` applies Dockerfile changes. It is optional when the existing local
images are already current. To recreate containers without rebuilding images:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml up -d
```

Inspect runtime state and connectivity without opening the UI:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml ps
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml logs controller
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml logs build-test-agent
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml logs docker-agent
```

Stop the stack while retaining Jenkins configuration:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml down
```

Agents may log an initial connection failure when they start before the
Controller is ready. The inbound-agent process retries automatically; a final
`INFO: Connected` confirms successful recovery.

## JCasC ownership and credentials

`jenkins/controller/jenkins.yaml` owns:

- the system message, zero Controller executors, and fixed inbound-agent port;
- both permanent-node definitions and their labels, remote roots, launchers,
  executor counts, and Remoting work-directory settings;
- the local security realm and authorization policy;
- the GitHub credential metadata; and
- the `cloud-native-api` Multibranch parent job.

The real administrator password and GitHub token are never present in the
tracked YAML. JCasC resolves `${JENKINS_ADMIN_PASSWORD}` and
`${JENKINS_GITHUB_TOKEN}` from the Controller environment at runtime. The
GitHub credential has a stable ID, `github-cloud-native-api`, which the branch
source and checkout logic reference without exposing the token as a normal
pipeline environment variable.

The fine-grained token is scoped to this repository. It can read repository
metadata, contents, and pull requests, and can write commit statuses so Jenkins
can publish `continuous-integration/jenkins/pr-merge`. It has no webhook
administration permission because the repository webhook is configured
manually. This keeps the write capability limited to build-result reporting.

## Multibranch discovery and checkout

Job DSL creates the `cloud-native-api` Multibranch parent. Its GitHub source
discovers internal branches and pull requests and accepts a revision only when
it contains the root `Jenkinsfile`.

The branch strategy builds branches that are not also represented by an open
pull request. Once a PR exists, Jenkins avoids executing the same change twice:
the branch child becomes orphaned and the `PR-<number>` child becomes active.
At most five orphaned children are retained for short-term history.

The pull-request strategy builds the `pr-merge` variant. Jenkins fetches the PR
head and its target branch, creates a temporary integration in the agent
workspace, and runs the pipeline against that result. This does not merge or
push anything on GitHub; it checks whether the proposed change works with the
current target branch before the real merge.

Jenkins first retrieves the `Jenkinsfile` from the discovered revision so it
can construct the pipeline and select `build-test-agent`. Declarative Pipeline
then performs the default full SCM checkout into the agent workspace. Standard
values such as `JOB_NAME`, `BRANCH_NAME`, `BUILD_NUMBER`, and `WORKSPACE` are
created by Jenkins at build time; they do not come from `jenkins/.env`.

## GitHub webhook relay

GitHub cannot call a Controller bound to the developer's `localhost`. The
repository webhook therefore sends `push` and `pull_request` events to a unique
Smee channel URL. The local `webhook-relay` container holds an outbound
connection to that channel and forwards each event through the private Compose
network:

```text
GitHub -> public Smee channel -> webhook-relay
       -> http://controller:8080/github-webhook/ -> Jenkins
```

No Jenkins UI port is exposed to the Internet. The channel URL is kept in
`JENKINS_WEBHOOK_RELAY_URL` inside the ignored `jenkins/.env`. Anyone who learns
that URL can submit development events to the channel, so the relay must be
stopped when not in use and must never be treated as production ingress.

The configured internal target is
`http://controller:8080/github-webhook/?source=smee`. Smee normalizes a target
ending in `/` by removing that slash. Jenkins distinguishes
`/github-webhook/` from `/github-webhook`: the latter redirects the POST, and
the GitHub plugin rejects the redirected request with HTTP 405. The harmless
query parameter preserves the required trailing-slash path; Jenkins ignores it.

Configure the repository webhook manually with the Smee URL as its payload
URL, `application/json` content, SSL verification enabled, no shared secret in
this local phase, and only push and pull-request events selected. A healthy
delivery produces `POST ... - 200` in the relay log.

The Jenkins commit status links back to `http://localhost:8081`. That link is
usable only from this development machine. Jenkins warns that `localhost` is
not a valid shared hostname because another user or server would resolve it to
itself; a production Controller would require a stable HTTPS DNS name.

## Reload and configuration drift

JCasC can be reapplied without restarting the Controller from **Manage
Jenkins -> Configuration as Code -> Reload existing configuration**. A
Controller restart also loads JCasC automatically. Rebuilding the image is
required first when the tracked local YAML itself changed.

Phase 14 verified drift by changing the managed system message in the UI to
`MANUAL DRIFT TEST`. The live API exposed the manual value. Reloading JCasC
restored `Cloud Native API Jenkins - managed by JCasC`, proving that the YAML,
not a conflicting UI edit, is the source of truth.

## Agent selection and manual verification

The current CI pipeline selects the Build/Test Agent by label:

```groovy
agent { label 'build-test' }
```

or:

```groovy
agent { label 'docker' }
```

Phase 13 verified the labels through temporary Freestyle jobs. The Build/Test
job checked out `develop` and executed:

```bash
./gradlew --version
```

The Docker job executed:

```bash
id
docker version
```

The `docker version` output must contain both `Client` and `Server`. The client
section proves that the CLI is installed; the server section proves that the
job can reach Docker Desktop's daemon.

## Docker socket trust boundary

Both static agents mount:

```text
/var/run/docker.sock:/var/run/docker.sock
```

This is Docker-outside-of-Docker: neither agent contains a second daemon.
Commands and API calls cross the socket and are executed by Docker Desktop's
daemon. On this local setup, the mounted socket is `root:root` with group
read/write permission. Compose therefore adds supplementary group ID `0` to the
otherwise unprivileged `jenkins` user in both containers.

Commands such as `docker --version` need only the local client. Commands such
as `docker version`, `docker build`, `docker run`, and `docker push` require
daemon access through the socket. Only the Docker Agent contains that CLI. The
Build/Test Agent instead uses Testcontainers' Java client to send Docker Engine
API requests through the socket for ephemeral PostgreSQL test infrastructure.

Socket access is effectively root-equivalent control over the host Docker
daemon: a job can create containers and mount host-visible paths. The Phase 15
Testcontainers requirement deliberately expands this boundary beyond the Phase
13 Docker Agent. Only trusted repository code may use either agent; application
image build/push commands remain restricted to the `docker` label. The stack is
local-only and must not expose either agent to untrusted jobs or public users.

## Why static inbound agents

Two static agents deliberately add operational work but make the distributed
Controller/Agent model visible and keep capabilities separated. An inbound
connection also avoids running SSH servers or storing SSH credentials in agent
containers. Dynamic cloud or Kubernetes agents are deferred because their
lifecycle automation would hide the bootstrap mechanics this learning phase is
designed to demonstrate.
