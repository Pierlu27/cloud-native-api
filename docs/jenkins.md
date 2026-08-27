# Jenkins Local Stack

Phase 13 introduces Jenkins as a second, independent CI/CD learning platform.
It does not replace the existing GitHub Actions delivery path. This phase
bootstraps the local infrastructure only; JCasC and actual Jenkins pipeline
logic belong to later phases.

## Architecture

The dedicated Compose stack contains three peer containers:

```text
Docker Desktop
├── controller
│   └── coordinates nodes, jobs, plugins, credentials, and build history
├── build-test-agent
│   └── executes source checkout and Gradle build/test workloads
└── docker-agent
    └── executes Docker CLI operations against Docker Desktop
```

The agents are not nested inside the Controller. All three containers share the
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

The project owns three reproducible images:

- `jenkins/controller/Dockerfile` pins the Jenkins LTS/JDK image and installs
  the versioned plugin list from `jenkins/controller/plugins.txt`;
- `jenkins/build-test-agent/Dockerfile` provides Java 25, Git, and curl. Gradle
  is supplied by the repository's versioned wrapper rather than installed
  globally; and
- `jenkins/docker-agent/Dockerfile` combines the official inbound-agent runtime
  with a pinned Docker CLI, Buildx, Compose, Git, and curl.

The baseline Controller plugins are Git, Pipeline, Credentials Binding, Docker
Pipeline, and Configuration as Code. The Dark Theme plugin is also installed
for the local UI. Installing the JCasC plugin in this phase does not enable
configuration as code; JCasC adoption starts in Phase 14.

## Persistent and disposable state

The named volume `cloud-native-api-jenkins-home` is mounted at
`/var/jenkins_home`. It preserves users, plugins, node definitions, credentials,
jobs, build history, and Controller configuration across container recreation.

The agents do not currently have persistent workspace volumes. Their checked
out workspaces and Gradle caches survive a normal container restart but are
discarded when the agent containers are removed and recreated. Source and
build configuration remain reproducible from Git and the Gradle Wrapper.

Use `docker compose down` for a normal teardown. Do not add `-v` unless losing
the local Jenkins installation is intentional:

```text
docker compose down       -> removes containers and network, keeps jenkins_home
docker compose down -v    -> also removes jenkins_home and its Jenkins data
```

## First-time bootstrap

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

## Agent selection and manual verification

Later pipelines will select agents by label:

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

The Docker Agent mounts:

```text
/var/run/docker.sock:/var/run/docker.sock
```

This is Docker-outside-of-Docker: the container has a Docker client but no
second daemon. Commands cross the socket and are executed by Docker Desktop's
daemon. On this local setup, the mounted socket is `root:root` with group
read/write permission. Compose therefore adds supplementary group ID `0` to
the otherwise unprivileged `jenkins` user.

Commands such as `docker --version` need only the local client. Commands such
as `docker version`, `docker build`, `docker run`, and `docker push` require
daemon access through the socket.

Socket access is effectively root-equivalent control over the host Docker
daemon: a job can create containers and mount host-visible paths. Only trusted
Docker stages should use the `docker` label. The Build/Test Agent deliberately
does not receive this mount. The stack is local-only and must not expose this
agent to untrusted jobs or public users.

## Why static inbound agents

Two static agents deliberately add operational work but make the distributed
Controller/Agent model visible and keep capabilities separated. An inbound
connection also avoids running SSH servers or storing SSH credentials in agent
containers. Dynamic cloud or Kubernetes agents are deferred because their
lifecycle automation would hide the bootstrap mechanics this learning phase is
designed to demonstrate.
