# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | yes       |

## Reporting a vulnerability

Use GitHub private vulnerability reporting on this repository (Security Advisories → Report a vulnerability). That is the preferred channel.

If you cannot use GitHub reporting, email ivan@quad4.io with a clear description, impact, and steps to reproduce.

Do not open a public issue for exploitable findings until a fix is available or we agree on disclosure.

We aim to acknowledge reports within a few days and ship fixes on a reasonable timeline for the severity.

## Scope

In scope: the nullray binary, sandbox (Landlock/seccomp), tool permissions, session storage under `~/.config/nullray/`, and GitHub Actions workflows in this repository.

Out of scope: third-party model providers, MCP servers you configure yourself, and general OS compromise outside the agent sandbox.

## Hardening notes

- Prefer `NULLRAY_PERMS=ask` until you trust a workspace.
- Keep secrets out of the agent path unless listed in `NULLRAY_SECRETS_ALLOW`.
- Releases use immutable GitHub releases and SHA-pinned Actions.
