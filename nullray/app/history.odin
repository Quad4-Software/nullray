// SPDX-License-Identifier: 0BSD
/*
Prompt input history (Up/Down) and paced stream/think reveal helpers.
*/

package app

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:unicode/utf8"
import "nullray:constants"
import "nullray:sandbox"
import "nullray:session"
import "nullray:store"
import "nullray:ui"

app_history_destroy :: proc(a: ^App) {
	for h in a.input_history {
		delete(h)
	}
	delete(a.input_history)
	a.input_history = {}
	a.input_hist_idx = -1
}

app_history_push :: proc(a: ^App, text: string) {
	t := strings.trim_space(text)
	if len(t) == 0 {
		return
	}
	if len(a.input_history) > 0 && a.input_history[len(a.input_history) - 1] == t {
		a.input_hist_idx = -1
		delete(a.input_draft)
		a.input_draft = ""
		return
	}
	append(&a.input_history, strings.clone(t))
	for len(a.input_history) > constants.INPUT_HISTORY_MAX {
		delete(a.input_history[0])
		ordered_remove(&a.input_history, 0)
	}
	a.input_hist_idx = -1
	delete(a.input_draft)
	a.input_draft = ""
}

@(private)
app_history_apply :: proc(a: ^App, text: string) {
	strings.builder_reset(&a.input)
	strings.write_string(&a.input, text)
	a.cursor = len(strings.to_string(a.input))
	a.suggest_sel = 0
	app_mark_dirty(a)
}

app_history_up :: proc(a: ^App) -> bool {
	if len(a.input_history) == 0 {
		return false
	}
	if a.input_hist_idx < 0 {
		delete(a.input_draft)
		a.input_draft = strings.clone(strings.to_string(a.input))
		a.input_hist_idx = len(a.input_history) - 1
	} else if a.input_hist_idx > 0 {
		a.input_hist_idx -= 1
	} else {
		return true
	}
	app_history_apply(a, a.input_history[a.input_hist_idx])
	return true
}

app_history_down :: proc(a: ^App) -> bool {
	if a.input_hist_idx < 0 {
		return false
	}
	if a.input_hist_idx + 1 >= len(a.input_history) {
		a.input_hist_idx = -1
		app_history_apply(a, a.input_draft)
		delete(a.input_draft)
		a.input_draft = ""
		return true
	}
	a.input_hist_idx += 1
	app_history_apply(a, a.input_history[a.input_hist_idx])
	return true
}

app_reveal_reset :: proc(a: ^App) {
	a.reveal_stream = 0
	a.reveal_think = 0
}

app_reveal_tick :: proc(a: ^App) -> bool {
	changed := false
	if a.session.has_thinking {
		full := strings.builder_len(a.session.thinking)
		if a.reveal_think < full {
			a.reveal_think = min(full, a.reveal_think + constants.STREAM_REVEAL_THINK_CHARS)
			changed = true
		}
	} else if a.reveal_think != 0 {
		a.reveal_think = 0
		changed = true
	}
	if a.session.has_streaming {
		full := strings.builder_len(a.session.streaming)
		if a.reveal_stream < full {
			a.reveal_stream = min(full, a.reveal_stream + constants.STREAM_REVEAL_CHARS)
			changed = true
		}
	} else if a.reveal_stream != 0 {
		a.reveal_stream = 0
		changed = true
	}
	return changed
}

app_reveal_prefix :: proc(text: string, rune_count: int, allocator := context.temp_allocator) -> string {
	if rune_count <= 0 {
		return ""
	}
	if rune_count >= utf8.rune_count_in_string(text) {
		return text
	}
	n := 0
	i := 0
	for i < len(text) {
		_, sz := utf8.decode_rune_in_string(text[i:])
		if sz <= 0 {
			break
		}
		n += 1
		i += sz
		if n >= rune_count {
			return strings.clone(text[:i], allocator)
		}
	}
	return text
}

/*
Wipe sessions, snapshots, crashes, runtime, env, keys, and mcp config.
Preserves nothing under the config dir except the directory itself.
*/
app_reset_all_state :: proc(a: ^App) -> bool {
	cfg := sandbox.resolve_config_dir(context.temp_allocator)
	session.crash_lock_clear(cfg)
	store.session_unlock(a.session.session_path)

	sess_dir, _ := filepath.join({cfg, "sessions"}, context.temp_allocator)
	snap_dir, _ := filepath.join({cfg, "snapshots"}, context.temp_allocator)
	crash_dir, _ := filepath.join({cfg, "crashes"}, context.temp_allocator)
	run_dir, _ := filepath.join({cfg, "runtime"}, context.temp_allocator)
	env_path, _ := filepath.join({cfg, "env"}, context.temp_allocator)
	keys_path, _ := filepath.join({cfg, "keys.ini"}, context.temp_allocator)
	mcp_path, _ := filepath.join({cfg, constants.MCP_CONFIG_FILE}, context.temp_allocator)

	_ = os.remove_all(sess_dir)
	_ = os.remove_all(snap_dir)
	_ = os.remove_all(crash_dir)
	_ = os.remove_all(run_dir)
	_ = os.remove(env_path)
	_ = os.remove(keys_path)
	_ = os.remove(mcp_path)

	os.unset_env(constants.ENV_SETUP_DONE)
	os.unset_env(constants.ENV_PROVIDER)
	os.unset_env(constants.ENV_MODEL)
	os.unset_env(constants.ENV_OPENROUTER_KEY)
	os.unset_env(constants.ENV_API_KEY)

	app_history_destroy(a)
	delete(a.input_draft)
	a.input_draft = ""
	app_sel_clear(a)
	app_view_close(a)
	app_reveal_reset(a)
	a.reset_pending = false

	_ = session.session_new(&a.session, "")
	session.session_set_status(&a.session, "reset complete")
	app_refresh_banner(a)
	app_setup_open(a, true)
	app_mark_dirty(a)
	return true
}
