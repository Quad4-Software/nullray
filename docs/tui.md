# TUI

The interface is a custom terminal UI: a cell buffer painted per frame,
platform backends for Linux, BSD/macOS, and Windows, and ANSI output.
No curses dependency.

## Layout

Top to bottom: a title bar, a session tab strip, the transcript, and a
multi-line input box with a status line under it. The busy indicator on
a tab shows a spinner, elapsed seconds, and the live tool. A `/view`
pane can open beside the transcript for files and artifacts.

## Tabs

Every tab is a live session. Work continues in background tabs, and a
tab flags when its turn finishes. The strip caps at 16 tabs and scrolls
with markers at the edges. Tabs are clickable, including the `+` button
that opens a new one.

| Control | Action |
|---------|--------|
| `ctrl-x` then `n` | New tab |
| `ctrl-x` then `w` | Close tab |
| `ctrl-x` then arrows | Move between tabs |
| `ctrl-x` then digits | Jump to tab |
| `ctrl-x` then `o` | Session picker |
| `f4` / `shift-tab` | Cycle tabs |
| `ctrl-g` | Close tab |
| `/tab` | list, new, open, next, prev, close, N |

Open tabs persist across restarts in `open_tabs` under the config dir.
`NULLRAY_SESSION` or `--session` wins over the saved layout.

## Input

Plain text input with multi-line editing. `/attach PATH` queues a file
or media attachment for the next message, `/attach` lists the queue,
`/attach clear` empties it. Images, audio, and video send as content
parts on providers that accept them.

Esc cancels a running turn in the active tab. While a turn is busy, Enter
injects the input as a mid-turn steer and Tab queues a follow-up for when
the turn ends. `/pause` stops after the current step, `/continue` resumes
with an optional note, `/stop` aborts.

## Collapsed blocks

Long tool results and thinking blocks fold to a marker line plus the
last few lines, so a `read_file` dump or a noisy `run_shell` does not
bury the conversation. Click a collapsed block to expand it, click again
to fold it back. `/expand` toggles every block at once and
`NULLRAY_COLLAPSE=0` turns folding off entirely.

## Markdown

Assistant messages render as markdown: headings, quotes, bullet and
numbered lists, horizontal rules, fenced code blocks with syntax colors
when the fence names a known language, and pipe tables drawn as boxed,
aligned columns. Inline `code`, **bold**, *italic* and ~~strike~~ are
styled, and links show as the underlined text followed by the target.

## History overlay

`/history` opens a scrollable view of the entire session, including
thinking and reasoning text rendered dim under a `think:` label. It
works while a turn is running, scrolls with the usual keys or the mouse
wheel, and Esc closes it.

## View pane

After a turn writes a file, the view pane auto-opens on that path.
`/view PATH` opens a file, `/artifact ID` opens an artifact from the LID
store, `/close` closes the pane, and `/view auto off` or
`NULLRAY_VIEW_AUTO=0` stops the auto-open.

A strip at the top lists recently viewed files. Clicking a name opens it,
and clicking anywhere else in the pane gives it focus (same as Tab).
While focused, Up/Down or PgUp/PgDn scroll and Left/Right or `[` `]`
cycle through the recent files. Esc closes the pane when the input box
is empty.

## Keybinds

`/keys` shows the active bindings. Presets live in
`~/.config/nullray/keys.ini` (`preset=default|neovim|emacs`) or come
from `--keys` / `NULLRAY_KEYS`. Individual binds can be overridden in
the same file.

## Themes

Built-ins: ink, ember, moss, slate, rose, mono, dusk. Switch with
`/theme NAME` or `--theme`, list with `/themes`.

## Terminal behavior

- `NULLRAY_COLOR=none|16|256|true` forces a color depth.
- `TERM=dumb` or an empty TERM skips mouse and alt-screen.
- `NO_COLOR` disables color.
- WSL falls back to `COLUMNS`/`LINES` when the ioctl reports zero size.
- `NULLRAY_MOUSE` and `NULLRAY_ALT_SCREEN` override detection.

## Notifications

When a background tab finishes or a print run ends, nullray sends a
notification. `NULLRAY_NOTIFY=auto|desktop|osc|bell|off` picks the
backend: a desktop helper (notify-send, osascript, PowerShell toast),
the OSC 9 escape (tmux-aware), or a terminal bell.

## Splash

The startup splash defaults on. `--no-splash`, `NULLRAY_SPLASH=0`, or
values false/off/no/disable skip it, and `--splash` forces it.
