# Terminal-Bench adapter

Point a Terminal-Bench agent adapter at nullray print mode. Build nullray first.

## Temp-dir only

Never use the nullray source tree as `--workspace`. Install the harness and run tasks under `/tmp` so agent edits and Docker scratch stay out of the repo.

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

The adapter copies `bin/nullray` into the task container, installs `libcurl4`, then runs:

```text
nullray --print --mode edit --perms yolo --bare --auto --workspace /app ...
```

Use lowercase `--run-id` values (Docker Compose project names reject uppercase).

Provider credentials come from the process environment or `~/.config/nullray/env`. Treat exit code 2 as a provider or runtime failure.
