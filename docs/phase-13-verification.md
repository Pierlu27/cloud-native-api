# Phase 13 Jenkins Bootstrap Verification

Local infrastructure verification date: 2026-08-27.

This document records sanitized text evidence for the Jenkins Controller and
two static inbound agents. Agent secrets, the initial administrator password,
and private account details are intentionally omitted. Screenshots are not
required.

## Stack and plugin verification

The dedicated `jenkins/docker-compose.yml` started three services:

```text
jenkins-controller-1
jenkins-build-test-agent-1
jenkins-docker-agent-1
```

The Controller UI was reachable at `http://localhost:8081`. The versioned
Controller image installed Git, Pipeline, Credentials Binding, Docker Pipeline,
Configuration as Code, and their transitive dependencies. Dark Theme was added
as an optional UI plugin. The initial setup completed successfully and did not
repeat after container recreation.

The Controller's built-in executor count was set to zero. Both static agents
were registered with one executor, label-restricted usage, remote root
`/home/jenkins/agent`, and inbound launch mode.

## Agent connectivity

The Build/Test Agent and Docker Agent both resolved the Controller through the
private Compose network. Their logs completed the same connection sequence:

```text
Agent discovery successful
Handshaking
Remote identity confirmed
INFO: Connected
```

The Nodes view then showed `build-test-agent` and `docker-agent` online. Each
used its own Jenkins-generated secret from the ignored local `jenkins/.env`.

## Build/Test Agent execution

A temporary Freestyle job named `phase13-build-agent-check` was restricted to
the `build-test` label. Jenkins assigned it to `build-test-agent`, checked out
the public `develop` branch, and executed:

```bash
./gradlew --version
```

The job reported `Finished: SUCCESS`. This verified Jenkins scheduling, Git
checkout, the project Gradle Wrapper, Java 25, and command execution on the
intended agent without a globally installed Gradle distribution.

## Docker Agent execution

A temporary Freestyle job named `phase13-docker-agent-check` was restricted to
the `docker` label and executed:

```bash
id
docker version
```

The identity output showed the unprivileged `jenkins` user with supplementary
group `0`. Docker reported a local client and a Docker Desktop server:

```text
Client: Docker CLI 29.7.2
Server: Docker Desktop 4.77.0, Engine 29.5.3
Negotiated API version: 1.54
```

The job reported `Finished: SUCCESS`. The server section confirms that the job
could open the mounted Docker socket and communicate with the daemon. The API
downgrade from the client's supported 1.55 to the server's supported 1.54 was
automatic version negotiation, not a failure.

## Persistence and reconnection

The complete stack was removed without deleting volumes:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml down
```

Compose removed the Controller, both agents, and the private network. It did
not remove the named `cloud-native-api-jenkins-home` volume. The stack was then
recreated from the existing images:

```bash
docker compose --env-file jenkins/.env -f jenkins/docker-compose.yml up -d
```

Both agents briefly retried while the Controller initialized, then logged
`INFO: Connected`. The UI retained the administrator setup, installed plugins,
node definitions, both verification jobs and their history, and the built-in
executor count of zero. No setup wizard or agent re-registration was required.

This test recreated containers; it did not rebuild their images. It confirms
that Controller state belongs to the named volume rather than to a disposable
container writable layer.
