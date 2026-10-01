# Sessions

Sessions are conversations that survive restarts. Each one is a
transcript file plus metadata under `~/.config/nullray/sessions/`.

## Storage

Transcripts write as `.msgpack` by default with a `.jsonl` fallback.
A session picks up a name when you save it with `/name` or
`--rename-session`. `nullray --session NAME` resumes or creates that
name on launch, and `/resume NAME` switches to it inside the TUI.
`-e` or `/ephemeral on` runs without loading or saving anything.

## Managing

```sh
nullray --list-sessions
nullray --search-sessions "deploy bug"
nullray --inspect-session mywork --follow
nullray --rename-session mywork --as sprint-42
nullray --export-session sprint-42 --out ./backup
nullray --import-session ./backup/sprint-42.jsonl --as restored
nullray --delete-session restored
```

In the TUI, `/sessions` lists, `/search` searches names and transcript
text, `/fork` copies a session to a new name, `/group` tags sessions
into a shared context group, and `/tab` manages open tabs. The tab
layout persists in `open_tabs` under the config dir.

## Usage tracking

Each session keeps token and cost metrics in `.usage.jsonl` plus a meta
summary. `/usage` shows them, `--usage` prints them in print mode, and
`/usage export PATH` writes a copy. Provider-reported cache hits show up
as `cache_read`. Cost only appears when the provider sends it. nullray
never invents cost from `/credits`. `NULLRAY_USAGE=0` stops writing,
and ephemeral sessions need `NULLRAY_USAGE_PERSIST=1` to record.

## Compaction and artifacts

Long sessions compress two ways. `/compact` summarizes old turns and
writes `.nullray/HANDOFF.md`. `/drop N` removes the last N user turns
with a backup saved first.

Under the hood the LID harness offloads big tool output: any tool dump
over `NULLRAY_ARTIFACT_CHARS` (default 3000) goes to
`.nullray/artifacts/` and the model sees a small envelope with status,
path, and an excerpt. `read_artifact` and `grep_artifact` pull pieces
back on demand. Provider history is a projection shaped by
`NULLRAY_PROJECTION_TURNS` and `NULLRAY_PROJECTION_TOOL_STUBS`, so the
model context stays small even as the transcript grows.
`NULLRAY_LID=0` turns the store and projection off.

## Checkpoints and undo

Every agent file write records a checkpoint. `/undo` reverts the last
write and `/checkpoint list|restore N|diff N` manages the rest. This is
separate from session transcripts: undo touches files, not messages.
