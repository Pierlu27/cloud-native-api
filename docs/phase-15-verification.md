# Phase 15 Jenkins CI verification

Runtime preparation verification date: 2026-09-01.

This is an incremental verification record. The Controller and Build/Test Agent
prerequisites are implemented; the real CI stages still need to replace the
Phase 14 placeholder `Jenkinsfile`. This document therefore does not mark Phase
15 complete.

## Static configuration and image build

Compose validation recognized the Controller volume plus the two new tool-data
volumes:

```text
jenkins_home
gradle_cache
dependency_check_data
```

The Controller and Build/Test Agent images rebuilt successfully. The Controller
plugin installer accepted the new pinned plugins, and the agent image copied the
static scanner from the official Gitleaks `v8.30.1` image.

The local and GitHub NVD checks confirmed only that non-empty secret entries
exist; their values were never printed. The new NVD key still requires a real
Dependency-Check request from the future pipeline before API validity is proven.

## Controller and agent startup

The recreated Controller completed plugin and JCasC initialization:

```text
Started all plugins
System config loaded
Processing provided DSL script
Jenkins is fully up and running
```

The Build/Test Agent retried while the Controller initialized, then completed:

```text
Agent discovery successful
Remote identity confirmed
Connected
```

The installed reporting-plugin versions are:

```text
junit 1424.vc64a_edde7777
warnings-ng 13.10233.va_9efb_20556c5
```

The runtime credentials file exposed the expected IDs without exposing secret
values:

```text
github-cloud-native-api
nvd-api-key
```

## Build/Test Agent capabilities

Runtime checks executed as the unprivileged Jenkins user with the supplementary
socket group:

```text
uid=1000(jenkins) gid=1000(jenkins) groups=1000(jenkins),0(root)
gitleaks version: v8.30.1
```

Both cache mount points were owned by `jenkins:jenkins` and accepted a write
test. The Docker Desktop socket was `root:root`, type socket, and group writable.
An HTTP Docker Engine ping sent through that Unix socket returned:

```text
OK
```

This proves daemon API access without installing the Docker CLI on the
Build/Test Agent. A full PostgreSQL Testcontainers run remains part of the
final Jenkinsfile validation.

## Named-volume persistence

One empty marker was written to each tool-data volume. The Build/Test Agent was
then force-recreated without its dependencies. Both markers remained available
in the new container:

```text
gradle_cache_marker=persisted
dependency_check_marker=persisted
```

The recreated agent subsequently reconnected to the existing JCasC node. The
temporary markers were removed after verification; the two named volumes remain
mounted and ready for real Gradle and NVD data.

## Remaining Phase 15 verification

- replace the placeholder `Jenkinsfile` with the complete CI stage sequence;
- execute the PostgreSQL Testcontainers test suite on the Build/Test Agent;
- prove the rotated NVD key through both Dependency-Check tasks;
- publish JUnit, Checkstyle, Dependency-Check, and redacted Gitleaks results;
- demonstrate the controlled test and synthetic-secret failure gates; and
- record the final clean Multibranch run and GitHub commit status.
