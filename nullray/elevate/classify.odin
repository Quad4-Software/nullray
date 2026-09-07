// SPDX-License-Identifier: 0BSD
/*
Token-aware elevation detection and hard denies for root shells / password args.
*/

package elevate

import "core:fmt"
import "core:strings"
import "core:unicode"

Classify :: struct {
	needs:            bool,
	backend:          Backend,
	deny_shell:       bool,
	deny_password_args: bool,
}

needs_elevate :: proc(cmd: string) -> bool {
	c := classify(cmd)
	return c.needs
}

classify :: proc(cmd: string) -> Classify {
	trimmed := strings.trim_space(cmd)
	if len(trimmed) == 0 {
		return {}
	}
	out: Classify
	if has_password_args(trimmed) {
		out.deny_password_args = true
		out.needs = true
		out.backend = backend_from_cmd(trimmed)
		return out
	}
	out.backend = backend_from_cmd(trimmed)
	if out.backend == .None {
		return out
	}
	out.needs = true
	out.deny_shell = is_interactive_root_shell(trimmed, out.backend)
	return out
}

@(private)
backend_from_cmd :: proc(cmd: string) -> Backend {
	if contains_word(cmd, "sudo") {
		return .Sudo
	}
	if contains_word(cmd, "doas") {
		return .Doas
	}
	if contains_word(cmd, "pkexec") {
		return .Pkexec
	}
	if contains_word(cmd, "runas") {
		return .Runas
	}
	if contains_word(cmd, "su") {
		return .Su
	}
	return .None
}

@(private)
contains_word :: proc(s, word: string) -> bool {
	n := len(word)
	if n == 0 || len(s) < n {
		return false
	}
	i := 0
	for i + n <= len(s) {
		if s[i:i + n] == word {
			before_ok := i == 0 || !is_word_char(rune(s[i - 1]))
			after_ok := i + n == len(s) || !is_word_char(rune(s[i + n]))
			if before_ok && after_ok {
				return true
			}
		}
		i += 1
	}
	return false
}

@(private)
is_word_char :: proc(r: rune) -> bool {
	return unicode.is_alpha(r) || unicode.is_digit(r) || r == '_'
}

@(private)
has_password_args :: proc(cmd: string) -> bool {
	lower := strings.to_lower(cmd, context.temp_allocator)
	if strings.contains(lower, "sudo -s") && strings.contains(lower, "<<<") {
		return true
	}
	if strings.contains(cmd, "sudo -S") || strings.contains(cmd, "sudo --stdin") {
		return true
	}
	if strings.contains(lower, "sudo_password=") || strings.contains(lower, "sudo_pass=") {
		return true
	}
	if strings.contains(cmd, "| sudo -S") || strings.contains(cmd, "|sudo -S") {
		return true
	}
	if strings.contains(cmd, "echo ") && strings.contains(cmd, "sudo -S") {
		return true
	}
	if strings.contains(cmd, "printf ") && strings.contains(cmd, "sudo -S") {
		return true
	}
	return false
}

@(private)
is_interactive_root_shell :: proc(cmd: string, backend: Backend) -> bool {
	switch backend {
	case .Sudo:
		if flag_present(cmd, "sudo", "i") || flag_present(cmd, "sudo", "s") {
			return true
		}
		if strings.contains(cmd, "sudo -i") || strings.contains(cmd, "sudo -s") {
			return true
		}
		if strings.contains(cmd, "sudo --login") || strings.contains(cmd, "sudo --shell") {
			return true
		}
	case .Doas:
		if flag_present(cmd, "doas", "s") || strings.contains(cmd, "doas -s") {
			return true
		}
		if ends_with_shell_bin(cmd, "doas") {
			return true
		}
	case .Su:
		return true
	case .Pkexec:
		if ends_with_shell_bin(cmd, "pkexec") {
			return true
		}
	case .Runas, .None:
	}
	return false
}

@(private)
flag_present :: proc(cmd, bin, flag: string) -> bool {
	// Match -flag or clustered short flags after bin token.
	tokens := strings.fields(cmd)
	defer delete(tokens)
	found_bin := false
	for tok in tokens {
		if !found_bin {
			if tok == bin || strings.has_suffix(tok, fmt.tprintf("/%s", bin)) {
				found_bin = true
			}
			continue
		}
		if tok == fmt.tprintf("-%s", flag) || tok == fmt.tprintf("--%s", flag) {
			return true
		}
		if len(tok) >= 2 && tok[0] == '-' && tok[1] != '-' {
			for c in tok[1:] {
				if c == rune(flag[0]) && len(flag) == 1 {
					return true
				}
			}
		}
		if tok[0] != '-' {
			break
		}
	}
	return false
}

@(private)
ends_with_shell_bin :: proc(cmd, bin: string) -> bool {
	shells := []string{"/bin/sh", "/bin/bash", "/bin/zsh", "/bin/fish", "bash", "sh", "zsh", "fish"}
	tokens := strings.fields(cmd)
	defer delete(tokens)
	seen := false
	for tok in tokens {
		if tok == bin || strings.has_suffix(tok, fmt.tprintf("/%s", bin)) {
			seen = true
			continue
		}
		if !seen {
			continue
		}
		if tok[0] == '-' {
			continue
		}
		for sh in shells {
			if tok == sh {
				return true
			}
		}
		return false
	}
	return false
}
