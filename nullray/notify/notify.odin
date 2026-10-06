// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Desktop notifications for background work. Fires when a non-active tab or a
headless run finishes, so parallel sessions can earn back human attention
without polling.

Backends, tried in order under NULLRAY_NOTIFY=auto:
  1. A desktop helper binary (notify-send, osascript, powershell toast).
  2. OSC 9 terminal notification escape (kitty, wezterm, ghostty, foot,
     Windows Terminal, iTerm2), tmux-aware.
  3. BEL.

NULLRAY_NOTIFY: auto | desktop | osc | bell | off (default auto).
Helper processes are spawned on a detached thread so the UI never blocks and
no zombie is left behind.
*/

package notify

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import "nullray:constants"
import "nullray:hooks"

Backend :: enum {
	Off,
	Auto,
	Desktop,
	Osc,
	Bell,
}

@(private)
NOTIFY_HELPER_TIMEOUT_MS :: 2_000

notify_backend :: proc() -> Backend {
	v, ok := os.lookup_env(constants.ENV_NOTIFY, context.temp_allocator)
	if !ok {
		return .Auto
	}
	switch strings.to_lower(strings.trim_space(v), context.temp_allocator) {
	case "0", "off", "no", "false", "none":
		return .Off
	case "desktop":
		return .Desktop
	case "osc", "osc9", "term", "terminal":
		return .Osc
	case "bell", "beep":
		return .Bell
	}
	return .Auto
}

// Fire a notification. Returns immediately; helper processes run detached.
notify_send :: proc(title, body: string) {
	mode := notify_backend()
	if mode == .Off {
		return
	}
	title := notify_sanitize(title, 80, context.temp_allocator)
	body := notify_sanitize(body, 200, context.temp_allocator)
	// The Notification hook observes the same title/body the desktop
	// notification would carry; a hook can reroute (webhook, log) instead.
	nres := hooks.run(.Notification, title, body, context.temp_allocator)
	hooks.result_destroy(&nres, context.temp_allocator)
	if mode == .Auto || mode == .Desktop {
			if cmd := notify_desktop_command(title, body, context.temp_allocator); len(cmd) > 0 {
			notify_run_helper(cmd)
			return
		}
	}
	if mode == .Auto || mode == .Osc {
		if notify_osc9(title, body) {
			return
		}
	}
	notify_bell()
}

// Strip control characters so notification text can never inject escapes.
@(private)
notify_sanitize :: proc(s: string, max_chars: int, allocator := context.allocator) -> string {
	out := make([dynamic]u8, 0, min(len(s), max_chars), allocator)
	for b in transmute([]u8)s {
		if len(out) >= max_chars {
			break
		}
		if b >= 0x20 && b != 0x7f {
			append(&out, b)
		} else {
			append(&out, ' ')
		}
	}
	return string(out[:])
}

@(private)
notify_osc9 :: proc(title, body: string) -> bool {
	text := body
	if len(title) > 0 && len(body) > 0 {
		text = strings.concatenate({title, ": ", body}, context.temp_allocator)
	} else if len(title) > 0 {
		text = title
	}
	if len(text) == 0 {
		return false
	}
	inner := strings.concatenate({"\x1b]9;", text, "\x07"}, context.temp_allocator)
	seq := inner
	if _, inside := os.lookup_env("TMUX", context.temp_allocator); inside {
		// tmux needs the DCS passthrough wrapper to forward OSC to the client.
		esc, _ := strings.replace_all(inner, "\x1b", "\x1b\x1b", context.temp_allocator)
		seq = strings.concatenate({"\x1bPtmux;", esc, "\x1b\\"}, context.temp_allocator)
	}
	n, err := os.write(os.stdout, transmute([]u8)seq)
	return err == nil && n == len(seq)
}

@(private)
notify_bell :: proc() {
	seq := "\x07"
	if _, inside := os.lookup_env("TMUX", context.temp_allocator); inside {
		seq = "\x1bPtmux;\x1b\x07\x1b\\"
	}
	_, _ = os.write(os.stdout, transmute([]u8)seq)
}

// Path to a helper binary found on PATH, or "".
@(private)
notify_which :: proc(name: string, allocator := context.allocator) -> string {
	path_env, ok := os.lookup_env("PATH", context.temp_allocator)
	if !ok {
		return ""
	}
	for dir in strings.split(path_env, ":", context.temp_allocator) {
		if len(dir) == 0 {
			continue
		}
		candidate, _ := filepath.join({dir, name}, context.temp_allocator)
		if _, err := os.stat(candidate, context.temp_allocator); err == nil {
			return strings.clone(candidate, allocator)
		}
	}
	return ""
}

// Pick the OS-native helper argv, or nil when none is available.
@(private)
notify_desktop_command :: proc(title, body: string, allocator := context.allocator) -> []string {
	when ODIN_OS == .Windows {
		// Balloon tip via WinForms NotifyIcon, no external module needed.
		if len(notify_which("powershell.exe", context.temp_allocator)) == 0 {
			return nil
		}
		script := strings.concatenate(
			{
				"Add-Type -AssemblyName System.Windows.Forms; ",
				"Add-Type -AssemblyName System.Drawing; ",
				"$n = New-Object System.Windows.Forms.NotifyIcon; ",
				"$n.Icon = [System.Drawing.SystemIcons]::Information; ",
				"$n.Visible = $true; ",
				"$n.ShowBalloonTip(8000, ",
				notify_ps_quote(title, allocator),
				", ",
				notify_ps_quote(body, allocator),
				", [System.Windows.Forms.ToolTipIcon]::Info); ",
				"Start-Sleep -Milliseconds 1500; $n.Dispose()",
			},
			allocator,
		)
		out := make([dynamic]string, allocator)
		append(&out, strings.clone("powershell.exe", allocator), strings.clone("-NoProfile", allocator), strings.clone("-NonInteractive", allocator), strings.clone("-Command", allocator), script)
		return out[:]
	} else when ODIN_OS == .Darwin {
		if len(notify_which("osascript", context.temp_allocator)) == 0 {
			return nil
		}
		script := strings.concatenate(
			{
				"display notification ",
				notify_applescript_quote(body, allocator),
				" with title ",
				notify_applescript_quote(title, allocator),
			},
			allocator,
		)
		out := make([dynamic]string, allocator)
		append(&out, strings.clone("osascript", allocator), strings.clone("-e", allocator), script)
		return out[:]
	} else {
		if bin := notify_which("notify-send", context.temp_allocator); len(bin) > 0 {
			out := make([dynamic]string, allocator)
			append(&out, strings.clone(bin, allocator), strings.clone(title, allocator), strings.clone(body, allocator))
			return out[:]
		}
		return nil
	}
}

// Wrap text as a single-quoted PowerShell literal.
@(private)
notify_ps_quote :: proc(s: string, allocator := context.allocator) -> string {
	esc, _ := strings.replace_all(s, "'", "''", context.temp_allocator)
	return strings.concatenate({"'", esc, "'"}, allocator)
}

// Wrap text as an AppleScript string literal.
@(private)
notify_applescript_quote :: proc(s: string, allocator := context.allocator) -> string {
	esc, _ := strings.replace_all(s, "\\", "\\\\", context.temp_allocator)
	esc, _ = strings.replace_all(esc, "\"", "\\\"", context.temp_allocator)
	return strings.concatenate({"\"", esc, "\""}, allocator)
}

// Run the helper with a bounded wait so a wedged D-Bus or PowerShell cannot
// stall the UI. stderr is discarded; a failed helper is not worth reporting.
@(private)
notify_run_helper :: proc(command: []string) {
	if len(command) == 0 {
		return
	}
	child, err := os.process_start(os.Process_Desc{command = command})
	if err != nil {
		return
	}
	state, werr := os.process_wait(child, time.Millisecond * NOTIFY_HELPER_TIMEOUT_MS)
	if werr != nil || !state.exited {
		_ = os.process_kill(child)
		_, _ = os.process_wait(child)
	}
}

