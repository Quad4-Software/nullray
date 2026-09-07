---
name: kube-ops
description: >
  Query and change Kubernetes clusters with NULLRAY_OPS=kube and an explicit
  kubeconfig allow path, without exposing credentials in output.
---

# Kubernetes operations

Use this skill for kubectl and cluster changes when kube access is intentionally enabled.

## Required env

Both must be set:

- `NULLRAY_OPS=kube` (or `full`)
- `NULLRAY_SECRETS_ALLOW` covering `~/.kube` or the exact kubeconfig path

Without the secrets allow entry, the kube ops profile stays blocked and `KUBECONFIG` is scrubbed from the environment.

## Context caution

Confirm the current context and namespace before mutating resources. A wrong context can hit production. Prefer read-only commands (`get`, `describe`, `logs`) until the target cluster is verified.

## Secrets

Never dump secrets, tokens, or kubeconfig contents into chat, commits, or tool results. Redact credential-shaped values. Do not `kubectl get secret -o yaml` unless the user explicitly needs it and accepts the exposure risk.

Shell and fetch tools can still reach the API if credentials are present. Treat cluster-admin kubeconfig as full host compromise.
