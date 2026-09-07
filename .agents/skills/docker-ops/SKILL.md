---
name: docker-ops
description: >
  Build and run containers with NULLRAY_OPS=docker, audit tools first, and
  compose lifecycle through shell when the Docker socket is granted.
---

# Docker operations

Use this skill when building images, running containers, or driving Compose in the workspace.

## Ops profile

Set `NULLRAY_OPS=docker` to grant the Docker socket and keep `DOCKER_HOST`. The profile also accepts `full`, which enables desktop and kube alongside docker.

Granting `docker.sock` with unix resolve often equals host Docker root. Treat every container and compose project as host-equivalent privilege.

## Audit first

Run `audit_dockerfile` and `audit_compose` before manual review or `docker compose up`. Fix findings from the [docker-secure](../docker-secure/SKILL.md) skill: pin base images, drop root where practical, avoid privileged mode, and keep secrets out of committed files.

## Compose lifecycle

Drive compose through shell when it is on the allow list:

- `docker compose up -d` to start
- `docker compose down` to stop and remove containers
- `docker compose ps` and `docker compose logs` to inspect

Add the exact prefix to `NULLRAY_SHELL_ALLOW` when `NULLRAY_PERMS=allow`.

## Caveats

A rootless container still shares the host kernel. Socket access is not a sandbox boundary. Clean audit output is not a security proof.
