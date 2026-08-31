# Phase 14 Jenkins as Code and GitHub Integration Verification

Local integration verification date: 2026-08-31.

This document records sanitized text evidence for JCasC, GitHub Multibranch
discovery, the temporary webhook relay, and configuration-drift recovery. Real
passwords, agent secrets, the GitHub token, and the Smee channel identifier are
intentionally omitted. Screenshots are not required.

## JCasC startup and strict secret resolution

The project-owned Controller image loaded
`/usr/share/jenkins/ref/jenkins.yaml` through `CASC_JENKINS_CONFIG`. A temporary
Controller with an empty volume started without the setup wizard and applied
the administrator, zero built-in executors, fixed inbound-agent port, system
message, and required plugins.

A separate negative startup test omitted the required administrator password.
With `CASC_STRICT_SECRET_RESOLUTION=true`, Jenkins stopped with a secret
resolution error instead of starting with a partially resolved configuration.

## Static nodes and GitHub credential

JCasC recreated `build-test-agent` and `docker-agent` on an empty temporary
Controller volume with their code-defined labels, executor counts, exclusive
usage, remote roots, inbound launchers, and Remoting work directories. Their
generated connection secrets remained outside the YAML. On the retained local
volume, both existing agent containers reconnected successfully after the
Controller recreation.

JCasC registered the `github-cloud-native-api` credential with global scope.
Its username and token were resolved from the ignored local environment. An
authenticated request verified repository metadata, content, and pull-request
read access without printing the token. The token was later granted only the
additional `Commit statuses: Read and write` permission required for Jenkins to
publish its build result; webhook administration remained disabled.

## Multibranch provisioning and initial scan

The JCasC `jobs` block ran Job DSL at Controller startup and created the
`cloud-native-api` Multibranch parent without manual UI configuration. The
generated job configuration contained the GitHub source, root `Jenkinsfile`,
branch and pull-request discovery traits, and the orphan policy:

```text
pruneDeadBranches = true
daysToKeep = -1
numToKeep = 5
```

An initial manual scan connected to GitHub and examined six branches and four
open pull requests. None yet contained the unpushed `Jenkinsfile`, so no child
job was created. This confirmed that discovery reads remote revisions rather
than the developer's working tree.

## Relay and GitHub ping

The Smee client image built successfully with `smee-client` 5.0.0 and connected
to the ignored local channel URL. The first GitHub ping reached Jenkins with
HTTP 405 because Smee removed the target's trailing slash and Jenkins redirected
`/github-webhook` to `/github-webhook/`. A direct comparison confirmed HTTP 200
with the slash and HTTP 302 without it.

The target was corrected to
`http://controller:8080/github-webhook/?source=smee`, preserving the required
path while leaving the query parameter semantically inert. Redelivering the
real GitHub ping produced:

```text
POST http://controller:8080/github-webhook/?source=smee - 200
PING webhook received from repo https://github.com/Pierlu27/cloud-native-api
```

## Branch and pull-request discovery

Pushing `feat/phase-14-jenkins-as-code` generated a GitHub push webhook without
a manual Jenkins scan. Jenkins processed the event in approximately 2.4
seconds, found the root `Jenkinsfile`, created the branch child, selected
`build-test-agent`, checked out commit `aa8af21`, and completed build 1 with
`Finished: SUCCESS`.

Opening [pull request #45](https://github.com/Pierlu27/cloud-native-api/pull/45)
generated a pull-request webhook. The configured branch strategy stopped
building the head as a duplicate branch and created `PR-45`. Jenkins fetched
the PR head and `develop`, performed the temporary `pr-merge` integration in
the agent workspace, and completed the placeholder pipeline successfully.

After the fine-grained token gained commit-status permission, GitHub recorded:

```text
continuous-integration/jenkins/pr-merge = success
description = This commit looks good
```

The status target points to `http://localhost:8081`, which is intentionally
usable only from the local development machine while the Controller is running.

## Configuration-drift recovery

The JCasC-managed system message was changed manually in the Jenkins UI to
`MANUAL DRIFT TEST`. The authenticated Jenkins API confirmed that the manual
value was active. Reloading the existing JCasC configuration returned HTTP 302
and reran the Job DSL block. A second API read returned:

```text
Cloud Native API Jenkins - managed by JCasC
```

This demonstrates that UI changes can alter the live persistent state, but a
JCasC reload restores the versioned declaration as the source of truth.
