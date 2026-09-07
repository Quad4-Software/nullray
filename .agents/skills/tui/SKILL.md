---
name: tui
description: >
  Custom nullray TUI: cell buffer, frame loop, keys, splash, binds, wide runes.
  Use when editing nullray/ui, nullray/app, nullray/config binds, or draw/input paths.
---

# TUI

Cell buffer UI. Paint cells. ANSI lives in term_present only.

Read `.agents/references/tui.md` for the file map. Read `.agents/references/footguns.md` before non-trivial UI or ownership changes.

## Frame loop

```
free_all(temp) -> query size -> maybe buffer_resize -> clear/draw/present -> poll_event -> on_tick
```

Wire-up in cmd/nullray:

```
loop_init -> app_init -> loop_run(app_draw, app_on_event, app_is_dirty, app_on_tick)
```

Each iteration frees temp. Do not store temp pointers past the frame.

## Paint rules

| Do | Do not |
|----|--------|
| buffer_put / buffer_text / widgets | write ANSI into Buffer |
| rune_cols / string_cols for width | use len(string) as display width |
| CELL_WIDE_CONT after wide primary | leave holes after wide glyphs |
| buffer_text_clip for chrome | let status and content collide |
| clear dirty at end of draw | leave dirty true forever |

Out of bounds put is a silent no-op. Control runes become space (sanitize_cell_rune). buffer_text stops at newline. Use wrap helpers for multi-line.

## Keys

- Esc alone waits ~8ms. No follow-up -> Esc. Second byte without [ or O -> Esc with alt.
- \n is Ctrl_J (insert newline). \r is Enter (submit, unless pasting).
- Bracketed paste: Paste_Start / Paste_End. While pasting, Enter inserts newline.
- Pushback is one byte. Do not expand lightly.
- stdin_ready is platform-split. Decode is shared.
- Cursor index is byte-based. Mid-rune UTF-8 breaks draw_input_line.

Binds: keys.ini preset= then NULLRAY_KEYS / --keys. Presets default | neovim | emacs.

Line-edit chords run before binds_resolve. Ctrl-C always quits (loop and binds). Busy Esc cancel is hardcoded in app_on_event. Binds.stop_agent is unused in resolve today.

## Splash

Default on. Off: NULLRAY_SPLASH=0|false|off|no|disable or --no-splash. Force: --splash or =1.

While splash_active, app_on_event drops all input (not queued). Splash keeps dirty for animation.

## Ownership (UI)

| Lifetime | Examples |
|----------|----------|
| frame temp | md_parse, highlight_line, fmt.tprintf, slash_matches |
| App permanent | credits_label, improve_undo, input Builder |
| Term/Buffer | cells, prev (destroy in close/resize) |

clipboard_paste returns owned text. delete after insert.

## Tests

odin test nullray/ui with ODIN_TEST_THREADS=1. buffer_test and markdown_test only. No live TTY tests. theme_set(INK), buffer_create, defer buffer_destroy.
