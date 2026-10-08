// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Slash commands: help, themes, view pane, clipboard.
*/

package app

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "nullray:config"
import "nullray:constants"
import "nullray:provider"
import "nullray:sandbox"
import "nullray:session"
import "nullray:skills"
import "nullray:store"
import "nullray:tools"
import "nullray:ui"

slash_cmd_help :: proc(a: ^App, args: string) {
	_ = args
	app_toggle_help(a)
}

slash_cmd_keys :: proc(a: ^App, args: string) {
	_ = args
	help := config.binds_help_text(a.binds, a.keys_preset)
	session.session_push_assistant(a.session, help)
	delete(help)
	session.session_set_status(a.session, "keys")
}

slash_cmd_setup :: proc(a: ^App, args: string) {
	_ = args
	app_setup_open(a, false)
}

slash_cmd_themes :: proc(a: ^App, args: string) {
	_ = args
	names := ui.theme_names()
	b: strings.Builder
	strings.builder_init(&b)
	strings.write_string(&b, "themes: ")
	for n, i in names {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, n)
	}
	fmt.sbprintf(&b, "\ncurrent: %s", ui.theme().name)
	out := strings.to_string(b)
	session.session_push_assistant(a.session, out)
	delete(out)
	session.session_set_status(a.session, "themes")
}

slash_cmd_skills :: proc(a: ^App, args: string) {
	id := strings.trim_space(args)
	if len(id) == 0 {
		list := skills.skills_list_text()
		session.session_push_assistant(a.session, list)
		delete(list)
		session.session_set_status(a.session, "skills")
		return
	}
	text, ok := skills.skills_show_text(id)
	if !ok {
		session.session_set_status(a.session, fmt.tprintf("unknown skill: %s · type /skills", id))
		return
	}
	session.session_push_assistant(a.session, text)
	delete(text)
	session.session_set_status(a.session, fmt.tprintf("skill %s", id))
}

slash_cmd_theme :: proc(a: ^App, args: string) {
	name := strings.trim_space(args)
	if len(name) == 0 {
		session.session_set_status(a.session, fmt.tprintf("theme %s", ui.theme().name))
		return
	}
	if !ui.theme_exists(name) {
		session.session_set_status(a.session, "usage: /theme ink|ember|moss|slate|rose|mono|dusk")
		return
	}
	ui.theme_set(ui.theme_by_name(name))
	if a.loop != nil {
		a.loop.theme = ui.theme()
		ui.loop_request_full_redraw(a.loop)
	}
	session.session_set_status(a.session, fmt.tprintf("theme %s", ui.theme().name))
	app_mark_dirty(a)
}

slash_cmd_tui :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	low := strings.to_lower(rest, context.temp_allocator)
	if len(rest) == 0 || low == "get" || low == "status" {
		mal := tools.ui_malleable_enabled()
		lock := tools.ui_global_locked()
		session.session_set_status(
			a.session,
			fmt.tprintf(
				"tui theme=%s malleable=%v lock=%v · /tui reset|lock|unlock|THEME",
				ui.theme().name,
				mal,
				lock,
			),
		)
		return
	}
	switch low {
	case "reset", "default", "clear":
		_ = ui.theme_clear_custom()
		base := "ink"
		if v, ok := os.lookup_env(constants.ENV_THEME, context.temp_allocator); ok && len(v) > 0 {
			base = v
		}
		t := ui.theme_by_name(base)
		ui.theme_set(t)
		if a.loop != nil {
			a.loop.theme = t
			ui.loop_request_full_redraw(a.loop)
		}
		session.session_set_status(a.session, "tui reset")
		app_mark_dirty(a)
	case "lock":
		os.set_env(constants.ENV_UI_LOCK, "1")
		session.session_set_status(a.session, "tui global lock on")
	case "unlock":
		os.unset_env(constants.ENV_UI_LOCK)
		session.session_set_status(a.session, "tui global lock off")
	case "off", "disable":
		os.set_env(constants.ENV_UI_MALLEABLE, "0")
		session.session_set_status(a.session, "tui malleable off (show_view/set_tui disabled)")
	case "on", "enable":
		os.unset_env(constants.ENV_UI_MALLEABLE)
		session.session_set_status(a.session, "tui malleable on")
	case:
		if ui.theme_exists(rest) {
			slash_cmd_theme(a, rest)
			return
		}
		session.session_set_status(a.session, "usage: /tui get|reset|lock|unlock|on|off|THEME")
	}
}

slash_cmd_copy :: proc(a: ^App, args: string) {
	_ = args
	if a.sel_has {
		_ = app_sel_copy(a)
		return
	}
	last := ""
	for i := len(a.session.messages) - 1; i >= 0; i -= 1 {
		if a.session.messages[i].role == .Assistant {
			last = a.session.messages[i].content
			break
		}
	}
	if len(last) == 0 {
		app_toast(a, "nothing to copy", .Warn)
		session.session_set_status(a.session, "nothing to copy")
		return
	}
	safe := sandbox.redact_secrets(last, context.temp_allocator)
	if ui.clipboard_copy(safe) {
		app_toast_ok(a, "copied to clipboard")
		session.session_set_status(a.session, "last reply on clipboard")
	} else {
		app_toast_error(a, "clipboard copy failed")
		session.session_set_status(a.session, "clipboard copy failed")
	}
}

app_media_clear :: proc(a: ^App) {
	provider.destroy_media_parts_owned(a.pending_media[:])
	a.pending_media = nil
}

app_attach_path :: proc(a: ^App, path: string) {
	abs := tools.resolve_path(path, context.temp_allocator)
	if sandbox.path_is_secret_blocked(abs) {
		session.session_set_status(a.session, "secret file blocked")
		return
	}
	kind, mime, is_media := provider.media_detect(abs)
	if is_media {
		if len(a.pending_media) >= constants.MEDIA_MAX_PARTS {
			session.session_set_status(a.session, "media queue full")
			return
		}
		part, merr := provider.media_load_file(abs, kind, mime)
		if len(merr) > 0 {
			session.session_set_status(a.session, fmt.tprintf("attach failed: %s", merr))
			return
		}
		append(&a.pending_media, part)
		note := ""
		if p := provider.registry_active(&a.registry); p != nil {
			if !provider.media_kind_supported(p, p.default_model, kind) {
				note = " (model may not accept it)"
			}
		}
		session.session_set_status(
			a.session,
			fmt.tprintf(
				"queued %s %s (%d pending)%s",
				provider.media_kind_string(kind),
				filepath.base(abs),
				len(a.pending_media),
				note,
			),
		)
		return
	}
	data, err := os.read_entire_file(abs, context.temp_allocator)
	if err != nil {
		session.session_set_status(a.session, "attach read failed")
		return
	}
	max_n := 32_000
	body := string(data)
	if len(body) > max_n {
		body = body[:max_n]
	}
	chunk := fmt.tprintf("\n\n[attached:%s]\n%s\n", path, body)
	app_insert_text(a, chunk)
	session.session_set_status(a.session, fmt.tprintf("attached %s", path))
}

slash_cmd_attach :: proc(a: ^App, args: string) {
	path := strings.trim_space(args)
	if len(path) == 0 {
		if len(a.pending_media) > 0 {
			names := make([dynamic]string, context.temp_allocator)
			for mp in a.pending_media {
				append(
					&names,
					fmt.tprintf(
						"%s:%s",
						provider.media_kind_string(mp.kind),
						mp.label,
					),
				)
			}
			session.session_set_status(
				a.session,
				fmt.tprintf(
					"queued: %s",
					strings.join(names[:], ", ", context.temp_allocator),
				),
			)
		} else {
			session.session_set_status(a.session, "usage: /attach path|clear")
		}
		return
	}
	if strings.to_lower(path, context.temp_allocator) == "clear" {
		app_media_clear(a)
		session.session_set_status(a.session, "media queue cleared")
		return
	}
	abs := tools.resolve_path(path, context.temp_allocator)
	if sandbox.path_is_secret_blocked(abs) {
		session.session_set_status(a.session, "secret file blocked")
		return
	}
	kind, _, is_media := provider.media_detect(abs)
	app_attach_path(a, path)
	if is_media && kind == .Image {
		_ = app_view_open(a, abs)
	}
}

slash_cmd_view :: proc(a: ^App, args: string) {
	path := strings.trim_space(args)
	if len(path) == 0 {
		if a.view_open {
			app_view_close(a)
			session.session_set_status(a.session, "view closed")
			return
		}
		session.session_set_status(a.session, "usage: /view path|auto on|off")
		return
	}
	low := strings.to_lower(path, context.temp_allocator)
	if strings.has_prefix(low, "auto") {
		rest := strings.trim_space(path[4:])
		r := strings.to_lower(rest, context.temp_allocator)
		switch r {
		case "", "on", "1", "true":
			a.view_auto = true
			session.session_set_status(a.session, "view auto on")
		case "off", "0", "false":
			a.view_auto = false
			session.session_set_status(a.session, "view auto off")
		case:
			session.session_set_status(a.session, "usage: /view auto on|off")
		}
		app_mark_dirty(a)
		return
	}
	_ = app_view_open(a, path)
}

slash_cmd_artifact :: proc(a: ^App, args: string) {
	id := strings.trim_space(args)
	if len(id) == 0 {
		session.session_set_status(a.session, "usage: /artifact ID")
		return
	}
	body, err := store.artifact_read(id, context.temp_allocator)
	if len(err) > 0 {
		session.session_set_status(a.session, err)
		return
	}
	title := fmt.tprintf("artifact:%s", id)
	_ = app_view_open_text(a, title, body)
}

slash_cmd_close :: proc(a: ^App, args: string) {
	rest := strings.trim_space(args)
	// Bare /close prefers the file view when open, otherwise the current tab.
	if len(rest) == 0 {
		if a.view_open {
			app_view_close(a)
			session.session_set_status(a.session, "view closed")
			return
		}
		app_tab_close(a, a.active_tab)
		return
	}
	low := strings.to_lower(rest, context.temp_allocator)
	switch low {
	case "view", "pane", "file":
		if !a.view_open {
			session.session_set_status(a.session, "no file view open")
			return
		}
		app_view_close(a)
		session.session_set_status(a.session, "view closed")
		return
	case "tab", "current", ".", "this":
		app_tab_close(a, a.active_tab)
		return
	}
	// /close tab <name|N>
	if strings.has_prefix(low, "tab ") {
		target := strings.trim_space(rest[len("tab "):])
		if idx, ok := app_tab_resolve(a, target); ok {
			app_tab_close(a, idx)
		} else {
			session.session_set_status(a.session, fmt.tprintf("no open tab matching %s", target))
		}
		return
	}
	// /close <name|N> closes that open tab.
	if idx, ok := app_tab_resolve(a, rest); ok {
		app_tab_close(a, idx)
		return
	}
	session.session_set_status(
		a.session,
		"usage: /close [tab|view|NAME|N]  (bare closes view if open, else current tab)",
	)
}
