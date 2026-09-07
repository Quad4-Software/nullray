---
name: docker-secure
description: >
  Review Dockerfiles and Compose files for pinned images, non-root execution,
  build provenance, restricted privileges, mounts, and secret handling.
---

# Secure containers

Use `audit_dockerfile` and `audit_compose` before manual review.

## Dockerfile checks

- Pin every base image by sha256 digest.
- Use a non-root final user.
- Keep build tools and credentials out of the final stage.
- Verify downloads before extraction or execution.
- Do not pipe network responses into a shell.
- Use BuildKit secret mounts for build credentials.
- Copy only required artifacts into the final image.

## Compose checks

- Do not enable privileged mode.
- Do not mount the Docker socket.
- Drop capabilities and add back only required entries.
- Use read-only filesystems and explicit writable mounts where practical.
- Bind published services to the intended interface.
- Keep secrets outside committed Compose files.

A rootless container still shares the host kernel. Image pins improve repeatability but do not prove the image is safe.
