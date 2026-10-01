# Sandbox

Tools run inside an OS sandbox. On Linux that means Landlock filesystem
rules plus a seccomp-bpf deny list and `NO_NEW_PRIVS`. macOS and Windows
have no working confinement backend in the current build, so sandbox
modes degrade to application policy there.

## Modes

`--sandbox` or `NULLRAY_SANDBOX`:

| Mode | Behavior |
|------|----------|
| off | No sandbox application |
| soft / warn | Continue with a warning if a control fails. Default |
| strict / on | Fail closed at startup if a requested control fails |

`strict` on a non-Linux host exits with "sandbox requires linux". Check
what is actually applied with `/ops` or `nullray --doctor`.

## What it does on Linux

- Landlock restricts which paths the process can reach after rules
  apply. ABI support is negotiated at runtime.
- seccomp denies a list of dangerous syscalls on amd64 (skipped on
  arm64).
- `NO_NEW_PRIVS` blocks privilege gain, so an in-process `sudo` cannot
  escalate.
- Known secret paths are blocked and secret-looking tool output is
  redacted. `NULLRAY_SECRETS_ALLOW` or `/secrets PATH` grants a specific
  path.
- Network: the docker socket needs Landlock ABI 9 with an explicit sock
  grant. There is no full network namespace isolation today.

## Ops profiles

`NULLRAY_OPS` widens the allowlists for a task instead of turning the
sandbox off. Profiles combine as a CSV list.

```sh
export NULLRAY_OPS=desktop          # ~/.config edits (ricing, dotfiles)
export NULLRAY_OPS=docker           # docker.sock access
export NULLRAY_OPS=kube             # kubeconfig, needs secrets allow too
export NULLRAY_OPS=desktop,docker
export NULLRAY_OPS=full             # broad, equivalent of unsandboxed paths
```

```sh
# Kubernetes needs an explicit secret grant for the kubeconfig
export NULLRAY_OPS=kube
export NULLRAY_SECRETS_ALLOW="$HOME/.kube"
```

Single paths: `NULLRAY_SANDBOX_EXTRA_RO` and `NULLRAY_SANDBOX_EXTRA_RW`
take absolute paths.

## Default grants

Two narrow grants stay on unless disabled. `NULLRAY_DOCS` adds
read-only access to tldr and rustup caches so doc lookup tools work.
`NULLRAY_TOOLCHAIN` adds read-write access to Go, Cargo, and npm caches
under home, and forces absolute `GOMODCACHE`/`GOCACHE`/`GOPATH` in
`run_shell` so builds do not litter the workspace.

## Elevated commands

`sudo`, `doas`, and `pkexec` go through `nullray/elevate`, a privilege
broker that runs before the sandbox applies. `NULLRAY_ELEVATE` controls
it:

- `ask`: the TUI prompts through askpass and the password never enters
  tool results or provider messages
- `deny`: refuse elevated commands (`--no-elevate` sets this)
- `ticket`: headless reuse of a prior TUI approval
- `NULLRAY_ASKPASS=/path/to/helper`: external askpass for headless runs

## VCS network

`vcs_push`, `vcs_pull`, `vcs_fetch`, and PR tools stay off until
`NULLRAY_VCS_NETWORK=1`. Force-push to main or master additionally needs
`NULLRAY_VCS_FORCE=1`.

## Inspecting posture

```sh
nullray --doctor   # sandbox mode, ops, extras, Landlock ABI, seccomp
/ops               # same info inside the TUI
```
