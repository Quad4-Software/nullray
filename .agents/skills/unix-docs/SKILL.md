---
name: unix-docs
description: >
  Answer Unix command and flag questions from installed manuals with
  read_man, apropos, read_tldr, read_info, and read_help before relying on
  memory. Use lang_doc for local language API docs.
---

# Unix documentation

Prefer local docs tools before inventing flags or APIs.

1. `read_tldr` for short examples when tldr is installed.
2. `apropos` then `read_man` for full manuals (section when names collide).
3. `read_info` for GNU texinfo nodes (coreutils, libc, make).
4. `read_help` for `command --help` when man or tldr is missing.
5. `lang_doc` with lang go, python, ruby, or rust for installed toolchain docs.
6. `fetch_url` only when you already know a public docs URL.

Prefer sections 1 for user commands, 2 for system calls, 3 for library calls, 5 for file formats, 7 for conventions, and 8 for administration.

Quote the exact option or behavior needed and name the manual section. Check platform-specific manuals because GNU, BSD, BusyBox, and POSIX behavior can differ.

Man and info require Linux tooling. tldr needs a local cache (`tldr --update`). Soft sandbox grants tealdeer and rustup caches read-only by default (`NULLRAY_DOCS=1`). Set `NULLRAY_DOCS=0` only if you want those closed. If manuals are unavailable, state that limitation and use `read_help` only when shell use is permitted for other work.
