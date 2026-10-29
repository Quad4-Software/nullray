// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Static checks for host inventory commands and suspicious network destinations.
*/

package tools

import "core:path/filepath"
import "core:strings"

/*
Block indicators reported in the October 2026 Qwen investigation and common
cloud instance-metadata destinations. These checks run before user overrides.
*/
suspicious_endpoint_reason :: proc(value: string) -> string {
	lower := strings.to_lower(value, context.temp_allocator)
	indicators := []struct { needle, reason: string }{
		{"sanmaohe.oss-cn-beijing.aliyuncs.com", "reported Alibaba OSS endpoint"},
		{"routify-file-proxy", "reported file-proxy host indicator"},
		{"169.254.169.254", "cloud instance metadata address"},
		{"2852039166", "encoded cloud instance metadata address"},
		{"0xa9fea9fe", "encoded cloud instance metadata address"},
		{"169.254.170.2", "container credential metadata address"},
		{"100.100.100.200", "Alibaba cloud metadata address"},
		{"fd00:ec2::254", "cloud instance metadata address"},
		{"metadata.google.internal", "cloud instance metadata hostname"},
		{"metadata.azure.com", "cloud instance metadata hostname"},
		{"http://metadata/", "cloud instance metadata hostname"},
		{"https://metadata/", "cloud instance metadata hostname"},
	}
	for item in indicators {
		if strings.contains(lower, item.needle) {
			return item.reason
		}
	}
	return ""
}

shell_system_info_reason :: proc(command: string) -> string {
	lower := strings.to_lower(command, context.temp_allocator)
	paths := []string{
		"/proc/", "/sys/", "/etc/os-release", "/etc/hostname",
		"/etc/machine-id", "/etc/resolv.conf", "/etc/issue",
		"os.uname", "os.environ", "os.getenv", "platform.", "process.env",
		"socket.gethostname", "getenv(",
		"get-ciminstance", "get-wmiobject", "get-computerinfo", "system_profiler",
	}
	for path in paths {
		if strings.contains(lower, path) {
			return "host information access is blocked"
		}
	}
	blocked := []string{
		"uname", "hostname", "hostnamectl", "whoami", "id", "groups",
		"printenv", "env", "ps", "pgrep", "lscpu", "lshw", "lsmem", "lsblk",
		"lsusb", "lspci", "dmidecode", "dmesg", "free", "uptime", "ip",
		"ifconfig", "ipconfig", "route", "netstat", "ss", "arp", "resolvectl",
		"dig", "nslookup", "host", "traceroute", "tracepath", "mtr", "nmap", "ping",
		"lsof", "fuser", "lsmod", "modinfo", "nproc", "getconf", "sysctl",
		"neofetch", "fastfetch", "inxi", "lsb_release", "systeminfo", "wmic",
		"sw_vers", "ioreg", "systemctl", "unshare", "nsenter",
		"which", "whereis",
	}
	if shell_command_has_any(blocked, command, 0) {
		return "host information or namespace probing command is blocked"
	}
	if shell_command_is_named(command, "ls", 0) && strings.contains(lower, "/tmp") {
		return "temporary-directory inventory is blocked"
	}
	return ""
}

shell_command_has_any :: proc(names: []string, command: string, depth: int) -> bool {
	if depth > 4 {
		return true
	}
	if shell_substitution_has_any(names, command, depth) {
		return true
	}
	start := 0
	quote: u8 = 0
	escaped := false
	for i in 0 ..= len(command) {
		sep := i == len(command)
		if !sep {
			c := command[i]
			if escaped {
				escaped = false
				continue
			}
			if c == '\\' && quote != '\'' {
				escaped = true
				continue
			}
			if quote != 0 {
				if c == quote {
					quote = 0
				}
				continue
			}
			if c == '\'' || c == '"' {
				quote = c
				continue
			}
			if c == '`' || c == ';' || c == '|' || c == '&' || c == '\n' || c == '(' || c == ')' {
				sep = true
			}
		}
		if !sep {
			continue
		}
		segment := shell_strip_quotes(command[start:i], context.temp_allocator)
		if shell_segment_has_any(names, segment, depth) {
			return true
		}
		start = i + 1
	}
	return false
}

@(private)
shell_substitution_has_any :: proc(names: []string, command: string, depth: int) -> bool {
	quote: u8 = 0
	escaped := false
	i := 0
	for i < len(command) {
		c := command[i]
		if escaped {
			escaped = false
			i += 1
			continue
		}
		if c == '\\' && quote != '\'' {
			escaped = true
			i += 1
			continue
		}
		if quote == '\'' {
			if c == '\'' {
				quote = 0
			}
			i += 1
			continue
		}
		if quote == '"' {
			if c == '"' {
				quote = 0
				i += 1
				continue
			}
		} else if c == '\'' || c == '"' {
			quote = c
			i += 1
			continue
		}
		if c == '$' && i + 1 < len(command) && command[i + 1] == '(' {
			body, end, found := shell_substitution_body(command, i + 2)
			if found && shell_command_has_any(names, body, depth + 1) {
				return true
			}
			if found {
				i = end + 1
				continue
			}
		}
		if c == '`' {
			end := strings.index_byte(command[i + 1:], '`')
			if end >= 0 {
				body := command[i + 1:i + 1 + end]
				if shell_command_has_any(names, body, depth + 1) {
					return true
				}
				i += end + 2
				continue
			}
		}
		i += 1
	}
	return false
}

@(private)
shell_substitution_body :: proc(command: string, start: int) -> (body: string, end: int, found: bool) {
	nesting := 1
	quote: u8 = 0
	escaped := false
	for i in start ..< len(command) {
		c := command[i]
		if escaped {
			escaped = false
			continue
		}
		if c == '\\' && quote != '\'' {
			escaped = true
			continue
		}
		if quote != 0 {
			if c == quote {
				quote = 0
			}
			continue
		}
		if c == '\'' || c == '"' {
			quote = c
			continue
		}
		if c == '(' {
			nesting += 1
		} else if c == ')' {
			nesting -= 1
			if nesting == 0 {
				return command[start:i], i, true
			}
		}
	}
	return "", 0, false
}

@(private)
shell_segment_has_any :: proc(names: []string, segment: string, depth: int) -> bool {
	fields := strings.fields(segment, context.temp_allocator)
	i := 0
	for i < len(fields) {
		word := fields[i]
		if strings.contains(word, "=") && !strings.has_prefix(word, "=") {
			i += 1
			continue
		}
		name := shell_executable_base(word)
		if name == "" {
			i += 1
			continue
		}
		if command_name_in(names, name) {
			return true
		}
		if shell_wrapper_name(name) {
			i += 1
			continue
		}
		if name == "sh" || name == "bash" || name == "dash" || name == "zsh" ||
		   name == "ksh" || name == "cmd.exe" {
			for j in i + 1 ..< len(fields) {
				if fields[j] == "-c" || strings.to_lower(fields[j], context.temp_allocator) == "/c" {
					inner := strings.join(fields[j + 1:], " ", context.temp_allocator)
					return shell_command_has_any(names, inner, depth + 1)
				}
			}
		}
		break
	}
	return false
}

@(private)
shell_command_is_named :: proc(command, expected: string, depth: int) -> bool {
	return shell_command_has_any([]string{expected}, command, depth)
}

@(private)
shell_executable_base :: proc(word: string) -> string {
	clean := strings.trim(word, "\"'`;,[]{}")
	if clean == "" || strings.has_prefix(clean, "-") {
		return ""
	}
	return strings.to_lower(filepath.base(clean), context.temp_allocator)
}

@(private)
shell_wrapper_name :: proc(name: string) -> bool {
	switch name {
	case "env", "command", "exec", "sudo", "doas", "pkexec", "nice", "nohup", "timeout", "time", "stdbuf", "busybox", "xargs":
		return true
	}
	return false
}

@(private)
command_name_in :: proc(names: []string, name: string) -> bool {
	for item in names {
		if item == name {
			return true
		}
	}
	return false
}

@(private)
shell_strip_quotes :: proc(value: string, allocator := context.temp_allocator) -> string {
	b: strings.Builder
	strings.builder_init(&b, allocator)
	quote: rune = 0
	escaped := false
	for c in value {
		if escaped {
			strings.write_rune(&b, c)
			escaped = false
			continue
		}
		if c == '\\' && quote != '\'' {
			escaped = true
			continue
		}
		if quote != 0 {
			if c == quote {
				quote = 0
			} else {
				strings.write_rune(&b, c)
			}
			continue
		}
		if c == '\'' || c == '"' || c == '`' {
			quote = c
			continue
		}
		strings.write_rune(&b, c)
	}
	if escaped {
		strings.write_byte(&b, '\\')
	}
	return strings.to_string(b)
}
