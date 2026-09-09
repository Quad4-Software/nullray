# Terminal-Bench adapter

Point a Terminal-Bench agent adapter at nullray print mode. Build nullray first.

## Temp-dir only

Never use the nullray source tree as `--workspace`. Install the harness and run tasks under `/tmp` so agent edits and Docker scratch stay out of the repo.

Adapter source of truth: `scripts/terminal-bench/nullray_agent.py`. Copy it into the temp `adapter/` dir or set `PYTHONPATH` to `scripts/terminal-bench`. Scorecard template: `SCORECARD.md`.

Example layout:

```text
/tmp/nullray-tbench-<stamp>/
  venv/                 # Python 3.12+ (3.14 breaks the tb CLI)
  adapter/nullray_agent.py
  datasets/             # downloaded terminal-bench-core
  runs/                 # harness output
```

## Run (from /tmp root)

```sh
make -C /path/to/nullray   # produces bin/nullray only

# Python 3.12 venv + terminal-bench (pin as needed)
python3.12 -m venv /tmp/nullray-tbench/venv
/tmp/nullray-tbench/venv/bin/pip install 'terminal-bench==0.2.18'

export OPENROUTER_API_KEY=...
export NULLRAY_BIN=/path/to/nullray/bin/nullray
export PYTHONPATH=/tmp/nullray-tbench/adapter

# Do not export T_BENCH_* on the host. The harness sets those itself
# include_os_env=True and empty/stale host values break container naming.

cd /tmp/nullray-tbench
./venv/bin/tb datasets download -d 'terminal-bench-core==0.1.1' --output-dir ./datasets
./venv/bin/tb run \
  --dataset-path ./datasets \
  --task-id hello-world \
  --agent-import-path nullray_agent:NullrayAgent \
  --agent-kwarg "nullray_bin=$NULLRAY_BIN" \
  --output-path ./runs \
  --run-id "nullray-hello-$(date -u +%Y%m%d-%H%M%S)"
```

The adapter copies `bin/nullray` into the task container, then runs:

```text
nullray --print --bare --no-subagents --mode edit --perms yolo --auto --print-strict --workspace /app ...
```

Adapter env inside the task container (via docker-cp'd `/tmp/nullray.env`, not tmux argv):

```text
NULLRAY_SANDBOX=off
NULLRAY_STRUCTURE=0
NULLRAY_AUTO=1
NULLRAY_AGENT_STEPS=300
NULLRAY_MAX_TOKENS=8192
NULLRAY_SHELL_TIMEOUT_MS=900000
NULLRAY_STREAM=0
NULLRAY_ELEVATE=deny
NULLRAY_SUBAGENTS=0
```

Wall timeout default is 2400s (`NULLRAY_TB_TIMEOUT`) to cover hard tasks such as UPET and Zork.

Also set `BUILDX_BUILDER=default`. Share a flock file (for example `/tmp/nullray-bench-full/.docker-build.lock`) so Terminal-Bench and sysadmin image builds do not race.

Use lowercase `--run-id` values (Docker Compose project names reject uppercase).

Provider credentials come from the process environment or `~/.config/nullray/env`. Treat exit code 2 as a provider or runtime failure.
