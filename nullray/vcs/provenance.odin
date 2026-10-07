// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
AI provenance for agent-made commits, following the Harness/Model/Method
trailer convention plus a machine-readable git note on
refs/notes/ai-provenance:

    Harness: nullray
    Model: <model>
    Method: <provider id, or Local for local backends>

Opt in with NULLRAY_AI_PROVENANCE=1. Repos or machines already running the
.githooks trailer hook (ai.harness git config present) keep ownership, and
SKIP_AI_HOOK=1 skips injection for parity with that setup.
*/

package vcs

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"
import dt "core:time/datetime"
import "nullray:constants"

provenance_active :: proc(repo: Repo) -> bool {
	if repo.kind != .Git {
		return false
	}
	if v, ok := os.lookup_env(constants.ENV_AI_PROVENANCE, context.temp_allocator); !ok ||
	   !env_value_truthy(v) {
		return false
	}
	if v, ok := os.lookup_env("SKIP_AI_HOOK", context.temp_allocator); ok && env_value_truthy(v) {
		return false
	}
	// A commit-msg hook that already stamps trailers owns provenance,
	// defer to it so commits do not gain two trailer sets.
	path_out, perr := run(
		repo,
		{"git", "rev-parse", "--git-path", "hooks/commit-msg"},
		context.temp_allocator,
	)
	if len(perr) > 0 {
		return false
	}
	hook := strings.trim_space(path_out)
	if len(hook) == 0 {
		return false
	}
	// --git-path may emit a path relative to the repo root.
	if !filepath.is_abs(hook) {
		hook, _ = filepath.join({repo.root, hook}, context.temp_allocator)
	}
	if !os.is_file(hook) {
		return true
	}
	if st, serr := os.stat(hook, context.temp_allocator); serr == nil {
		when ODIN_OS == .Windows {
			return true
		} else {
			return .Execute_User not_in st.mode
		}
	}
	return false
}

@(private)
env_value_truthy :: proc(v: string) -> bool {
	l := strings.to_lower(v, context.temp_allocator)
	return l == "1" || l == "true" || l == "yes" || l == "on"
}

// Harness/model/method labels. Resolution order per field:
// NULLRAY_AI_HARNESS/_MODEL/_METHOD env, then ai.* git config, then the
// live session values. The git-config keys match the .githooks convention.
provenance_identity :: proc(repo: Repo, model, method: string, allocator := context.allocator) -> (string, string, string) {
	harness := "nullray"
	m := len(model) > 0 ? model : "unknown"
	meth := len(method) > 0 ? method : "unknown"
	if v, _ := config_get(repo, "ai.harness"); len(v) > 0 {
		harness = strings.clone(v, allocator)
	}
	if v, _ := config_get(repo, "ai.model"); len(v) > 0 {
		m = v
	}
	if v, _ := config_get(repo, "ai.method"); len(v) > 0 {
		meth = v
	}
	if v, ok := os.lookup_env("NULLRAY_AI_HARNESS", context.temp_allocator); ok && len(v) > 0 {
		harness = strings.clone(v, allocator)
	}
	if v, ok := os.lookup_env("NULLRAY_AI_MODEL", context.temp_allocator); ok && len(v) > 0 {
		m = strings.clone(v, allocator)
	}
	if v, ok := os.lookup_env("NULLRAY_AI_METHOD", context.temp_allocator); ok && len(v) > 0 {
		meth = strings.clone(v, allocator)
	}
	return harness, m, meth
}

@(private)
config_get :: proc(repo: Repo, key: string) -> (string, bool) {
	out, err := run(repo, {"git", "config", "--get", key}, context.temp_allocator)
	if len(err) > 0 {
		return "", false
	}
	return strings.trim_space(out), true
}

// Append Harness/Model/Method trailers to the commit message. Returns the
// original message unchanged when trailers are already present.
provenance_message :: proc(message, harness, model, method: string, allocator := context.allocator) -> string {
	if strings.contains(message, "\nHarness:") || strings.has_prefix(message, "Harness:") {
		return strings.clone(message, allocator)
	}
	trimmed := strings.trim_right(message, " \t\n")
	return fmt.aprintf(
		"%s\n\nHarness: %s\nModel: %s\nMethod: %s",
		trimmed,
		harness,
		len(model) > 0 ? model : "unknown",
		len(method) > 0 ? method : "unknown",
		allocator = allocator,
	)
}

// Attach the JSON provenance note to HEAD under refs/notes/ai-provenance.
// Best effort: notes failures never fail the commit.
provenance_note :: proc(repo: Repo, model, method: string) {
	harness, m, meth := provenance_identity(repo, model, method, context.temp_allocator)
	sha_out, sha_err := run(repo, {"git", "rev-parse", "HEAD"}, context.temp_allocator)
	if len(sha_err) > 0 {
		return
	}
	sha := strings.trim_space(sha_out)
	if len(sha) == 0 {
		return
	}
	note := fmt.aprintf(
		"{{\"harness\":\"%s\",\"model\":\"%s\",\"method\":\"%s\",\"ts\":\"%s\"}}",
		json_escape(harness, context.temp_allocator),
		json_escape(m, context.temp_allocator),
		json_escape(meth, context.temp_allocator),
		rfc3339_utc(time.now(), context.temp_allocator),
		allocator = context.temp_allocator,
	)
	_, _ = run(
		repo,
		{"git", "notes", "--ref=ai-provenance", "add", "-f", sha, "-m", note},
		context.temp_allocator,
	)
}

@(private)
json_escape :: proc(s: string, allocator := context.allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	for r in s {
		switch r {
		case '"': strings.write_string(&b, "\\\"")
		case '\\': strings.write_string(&b, "\\\\")
		case '\n': strings.write_string(&b, "\\n")
		case '\r': strings.write_string(&b, "\\r")
		case '\t': strings.write_string(&b, "\\t")
		case:
			if r < 0x20 {
				fmt.sbprintf(&b, "\\u%04x", int(r))
			} else {
				strings.write_rune(&b, r)
			}
		}
	}
	return strings.to_string(b)
}

@(private)
rfc3339_utc :: proc(t: time.Time, allocator := context.allocator) -> string {
	c, ok := time.time_to_datetime(t)
	if !ok {
		return strings.clone("1970-01-01T00:00:00Z", allocator)
	}
	return fmt.aprintf(
		"%04d-%02d-%02dT%02d:%02d:%02dZ",
		c.date.year, int(c.date.month), c.date.day,
		c.time.hour, c.time.minute, c.time.second,
		allocator = allocator,
	)
}
