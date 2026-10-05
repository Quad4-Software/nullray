// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
TCP port allowlist for net=Local: defaults plus ports parsed from
provider host env vars and NULLRAY_SANDBOX_PORTS.
*/

package sandbox

import "core:os"
import "core:strconv"
import "core:strings"
import "nullray:constants"

// TCP connect/bind allowlist for net=Local: cloud HTTPS plus the default ports
// of the local model hosts nullray knows about.
default_net_ports :: proc(allocator := context.allocator) -> [dynamic]u64 {
	ports := make([dynamic]u64, allocator)
	// 53 covers DNS so hostname-based provider URLs still resolve.
	// 8000 is the laya-serve default for NULLRAY_JUDGE=laya.
	append(&ports, 443, 80, 53, 11434, 1234, 8080, 9931, 8000)
	return ports
}

net_ports_from_env :: proc(ports: ^[dynamic]u64) {
	append_url_port(ports, env_or_empty(constants.ENV_OLLAMA_HOST))
	append_url_port(ports, env_or_empty(constants.ENV_LMSTUDIO_HOST))
	append_url_port(ports, env_or_empty(constants.ENV_LLAMACPP_HOST))
	append_url_port(ports, env_or_empty(constants.ENV_BASE_URL))
	append_url_port(ports, env_or_empty(constants.ENV_OPENAI_BASE))
	// A judge spec of the form kind:model@url may pin a custom endpoint.
	if v, ok := os.lookup_env("NULLRAY_JUDGE", context.temp_allocator); ok {
		if i := strings.index(v, "@"); i >= 0 {
			append_url_port(ports, v[i + 1:])
		}
	}
	if v, ok := os.lookup_env(constants.ENV_SANDBOX_PORTS, context.temp_allocator); ok && len(v) > 0 {
		for part in strings.split(v, ",", context.temp_allocator) {
			if n, ok2 := strconv.parse_u64_of_base(strings.trim_space(part), 10); ok2 && n >= 1 && n <= 65535 {
				append_unique_port(ports, n)
			}
		}
	}
}

@(private)
env_or_empty :: proc(name: string) -> string {
	v, _ := os.lookup_env(name, context.temp_allocator)
	return v
}

@(private)
append_unique_port :: proc(ports: ^[dynamic]u64, port: u64) {
	for p in ports {
		if p == port {
			return
		}
	}
	append(ports, port)
}

// Pull the destination port out of a provider base URL so a configured local
// server on a custom port stays reachable under net=local.
@(private)
append_url_port :: proc(ports: ^[dynamic]u64, raw: string) {
	if port, ok := net_port_from_url(raw); ok {
		append_unique_port(ports, port)
	}
}

net_port_from_url :: proc(raw: string) -> (port: u64, ok: bool) {
	s := strings.trim_space(raw)
	if len(s) == 0 {
		return 0, false
	}
	scheme := ""
	if i := strings.index(s, "://"); i >= 0 {
		scheme = s[:i]
		s = s[i + 3:]
	}
	if i := strings.index_byte(s, '/'); i >= 0 {
		s = s[:i]
	}
	if i := strings.index(s, "@"); i >= 0 {
		s = s[i + 1:]
	}
	// Bracketed IPv6: [::1]:8080
	if strings.has_prefix(s, "[") {
		end := strings.index(s, "]")
		if end < 0 {
			return 0, false
		}
		rest := s[end + 1:]
		if strings.has_prefix(rest, ":") {
			return parse_port_digits(rest[1:])
		}
		return default_scheme_port(scheme)
	}
	if i := strings.last_index_byte(s, ':'); i >= 0 {
		return parse_port_digits(s[i + 1:])
	}
	return default_scheme_port(scheme)
}

@(private)
parse_port_digits :: proc(digits: string) -> (u64, bool) {
	if len(digits) == 0 {
		return 0, false
	}
	n, ok := strconv.parse_u64_of_base(digits, 10)
	if !ok || n < 1 || n > 65535 {
		return 0, false
	}
	return n, true
}

@(private)
default_scheme_port :: proc(scheme: string) -> (u64, bool) {
	switch scheme {
	case "https":
		return 443, true
	case "http":
		return 80, true
	}
	return 0, false
}
