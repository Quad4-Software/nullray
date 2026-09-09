# TUI map

Dense file map for nullray/ui, nullray/app, nullray/config.

## ui/

| File | Owns |
|------|------|
| term.odin | Term, init/close, query_size, present, invalidate, color mode |
| term_linux.odin | #+build linux raw + winsize |
| term_bsd.odin | #+build darwin, freebsd, netbsd, openbsd |
| term_windows.odin | #+build windows console |
| buffer.odin | Cell, Buffer, create/destroy/resize/clear/put/text/text_clip |
| width.odin | CELL_WIDE_CONT, rune_cols, string_cols |
| edit.odin | rune-boundary cursor helpers |
| keys.odin | Key, Event, poll_event, decode_csi, UTF-8 lead, pushback |
| keys_unix.odin | #+build !windows stdin_ready (poll) |
| keys_windows.odin | #+build windows stdin_ready |
| loop.odin | Loop, run, request_full_redraw |
| widgets.odin | box, status bar, input line, wrapped text |
| markdown.odin | md_parse, block classifiers |
| markdown_wrap.odin | word_wrap_lines |
| markdown_draw.odin | draw_md_text_wrapped, inline ticks |
| highlight.odin | highlight_line |
| theme.odin / color.odin / anim.odin / clipboard.odin | look and paste |

## app/

| File | Owns |
|------|------|
| app.odin | App, init/destroy, dirty, on_tick |
| app_credits.odin | OpenRouter credits, hide-sensitive |
| setup.odin | setup wizard state and open/close |
| setup_flow.odin | setup models, reasoning, save |
| setup_draw.odin | setup overlay draw |
| setup_input.odin | setup keyboard input |
| view.odin | view pane open, layout, write paths |
| view_draw.odin | app_draw_view_pane |
| draw_blocks.odin | Transcript_Block, md append, heights |
| draw_transcript.odin | collect and paint transcript blocks |
| draw.odin | app_draw, help/status/suggest overlays |
| input.odin | app_on_event, submit orchestration |
| input_overlay.odin | help/status overlay event branches |
| input_dispatch.odin | view/suggest/bind/default event branches |
| input_edit.odin | line edit and scroll helpers |
| input_improve.odin | improve prompt job |
| input_draw.odin | multiline input box, expand hit testing |
| layout_cache.odin | transcript height cache, view_auto env |
| splash.odin | splash timer + draw |
| slash.odin | app_handle_slash dispatch |
| slash_session.odin | session slash handlers |
| slash_agent.odin | agent/model slash handlers |
| slash_ops.odin | status/ops/verify slash handlers |
| slash_ui.odin | help/theme/view slash handlers |
| commands.odin | slash catalog |

## config/

| File | Owns |
|------|------|
| binds.odin | Binds, Key_Preset, load_binds |
| binds_resolve.odin | binds_resolve, help text, key names |
| config.odin | ~/.config/nullray/env |

## Constants (UI-related)

POLL_TIMEOUT_MS 50, DEFAULT_TERM_COLS 80, DEFAULT_TERM_ROWS 24, MAX_INPUT_CHARS 16384, INPUT_MAX_ROWS 8, SPINNER_FRAME_MS 80, STATUS_HOLD_MS 1200, ENV_SPLASH, ENV_KEYS, ENV_VIEW_AUTO.

## Diff present

Term.prev + has_prev. Size change or term_invalidate forces full redraw. Theme switch must update Loop.theme and invalidate or stale SGR remains.
