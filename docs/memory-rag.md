# Memory and RAG

nullray keeps two kinds of project knowledge: plain memory files the
agent writes, and an optional vector index for retrieval.

## Project memory

`.nullray/memory/` under the workspace holds learned observations. The
layout is a `MEMORY.md` index, small key files, and an optional
`topics/` directory for longer notes. The agent writes lessons here when
it learns something worth keeping, like a gotcha about the build or a
naming rule.

Scoped recall keys inject a lesson exactly when it matters:

- `recall.path.<glob>` triggers when a tool touches a matching path
- `recall.cmd.<substr>` triggers on shell commands containing the text
- `recall.tool.<name>` triggers when a specific tool runs

`NULLRAY_RECALL=0` disables recall injection.

## RAG

`NULLRAY_RAG=auto|1|0` controls the vector index under `.nullray/rag/`.
`NULLRAY_EMBED_PROVIDER` and `NULLRAY_EMBED_MODEL` pick the embedder,
and a local chat model pairs best with a local embedder so nothing
leaves the machine.

Tools the agent gets:

| Tool | Purpose |
|------|---------|
| `rag_status` | Index state |
| `rag_query` | Query, `scope=all\|memory\|code` |
| `rag_reindex` | Rebuild, `scope=memory\|code\|all` |

`NULLRAY_RAG_CODE=1` opts into a live-tree lane: reindexing walks the
workspace, skips denylisted directories, caps per-file and total bytes,
screens for secrets, and marks stale hits by mtime.

## Traces and handoffs

When the post-edit verify gate fails, nullray writes a draft trace to
`.nullray/traces/` with a failure category for human review. `/compact`
summarizes long sessions and writes `.nullray/HANDOFF.md` so a fresh
session can pick up context without the full transcript.
