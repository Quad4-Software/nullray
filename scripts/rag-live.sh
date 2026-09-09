#!/usr/bin/env bash
# Live RAG smoke: OpenRouter embeddings + Mercury 2.5 recall.
# Requires OPENROUTER_API_KEY in the environment (never commit keys).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${NULLRAY_BIN:-$ROOT/bin/nullray}"
TMP="${TMPDIR:-/tmp}/nullray-rag-live-$$"
FACT_TOKEN="raglive_zebra_42_$(date +%s)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  if [[ -f "$HOME/.config/nullray/env" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source <(grep -E '^OPENROUTER_API_KEY=' "$HOME/.config/nullray/env" || true)
    set +a
  fi
fi

if [[ -z "${OPENROUTER_API_KEY:-}" ]]; then
  echo "rag-live: skip (OPENROUTER_API_KEY unset)"
  exit 0
fi

if [[ ! -x "$BIN" ]]; then
  echo "rag-live: missing binary $BIN (run make first)"
  exit 1
fi

mkdir -p "$TMP"
export NULLRAY_WORKSPACE="$TMP"
export NULLRAY_SANDBOX=off
export NULLRAY_PROVIDER=openrouter
export NULLRAY_RAG=1
export NULLRAY_EMBED_PROVIDER=openrouter
export NULLRAY_EMBED_MODEL="${NULLRAY_EMBED_MODEL:-openai/text-embedding-3-small}"
export NULLRAY_MODEL="${NULLRAY_MODEL:-inception/mercury-2.5}"
export NULLRAY_EPHEMERAL=1
export NULLRAY_STREAM=0
export NULLRAY_AGENT_STEPS=8
export NULLRAY_MODE=edit
export NULLRAY_GATE=yolo

echo "rag-live: embed identity model=$NULLRAY_EMBED_MODEL chat=$NULLRAY_MODEL ws=$TMP"

# Seed memory via tool-less helper: write entries then reindex through print tools.
# Use a tiny print turn that only puts memory then queries.
SEED_PROMPT=$(cat <<EOF
Use memory_put with key pref.raglive and value exactly: The secret project codename is ${FACT_TOKEN}.
Then call rag_reindex.
Then call rag_query with query: project codename.
Finally reply with one line containing only the codename token from memory.
EOF
)

OUT="$TMP/out.txt"
set +e
"$BIN" --print --provider openrouter --model "$NULLRAY_MODEL" "$SEED_PROMPT" >"$OUT" 2>"$TMP/err.txt"
EC=$?
set -e

echo "rag-live: print exit=$EC"
if [[ ! -s "$OUT" ]]; then
  echo "rag-live: empty stdout"
  cat "$TMP/err.txt" || true
  exit 1
fi

if ! grep -q "$FACT_TOKEN" "$OUT"; then
  echo "rag-live: FAIL did not recall $FACT_TOKEN"
  echo "--- stdout ---"
  cat "$OUT"
  echo "--- stderr ---"
  cat "$TMP/err.txt" || true
  exit 1
fi

echo "rag-live: ok (recalled $FACT_TOKEN)"

# Optional Ollama path
if curl -sf --max-time 1 http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  if curl -sf --max-time 1 http://127.0.0.1:11434/api/tags | grep -q nomic-embed-text; then
    echo "rag-live: ollama nomic-embed-text present (optional local embed skipped in this script)"
  fi
fi

exit 0
