---
name: structure
description: Keep source files within workspace line limits and split oversized files.
---

# Structure

Load this skill before edits that may create or enlarge a source file.

Read `.nullray/policy.json` when present. The defaults are 400 maximum lines and a warning at 250 lines.

Use audit_structure before broad refactors. Split files reported as godfile by responsibility. Preserve package boundaries and public APIs unless the task requires an API change.

Do not grow a file past max_file_lines. Existing oversized files may be reduced or left unchanged. Use allow_godfile only when the user explicitly accepts an oversized file or generated code cannot be split safely.

Set `NULLRAY_STRUCTURE=0` only for a deliberate workspace-wide bypass.
