---
name: unix-docs
description: >
  Answer Unix command and flag questions from installed manual pages with
  read_man and apropos before relying on memory.
---

# Unix documentation

Use `apropos` to find a manual when the command name is unknown. Use `read_man` with a section when names collide.

Prefer sections 1 for user commands, 2 for system calls, 3 for library calls, 5 for file formats, 7 for conventions, and 8 for administration.

Quote the exact option or behavior needed and name the manual section. Check platform-specific manuals because GNU, BSD, BusyBox, and POSIX behavior can differ.

The tools require Linux with man-db or mandoc. If manuals are unavailable, state that limitation and inspect local `--help` output only when shell use is permitted.
