// SPDX-License-Identifier: 0BSD
/*
Rewrite elevated commands for askpass (sudo -A, DOAS_ASKPASS).
*/

package elevate

import "core:fmt"
import "core:strings"

Rewrite :: struct {
	command:   string,
	sudo_askpass: string,
	doas_askpass: string,
	use_ticket: bool,
}

rewrite_for_elevate :: proc(
	cmd: string,
	backend: Backend,
	askpass: string,
	use_ticket: bool,
	allocator := context.allocator,
) -> Rewrite {
	out: Rewrite
	out.use_ticket = use_ticket
	switch backend {
	case .Sudo:
		out.sudo_askpass = strings.clone(askpass, allocator)
		out.command = rewrite_sudo(cmd, use_ticket, allocator)
	case .Doas:
		out.doas_askpass = strings.clone(askpass, allocator)
		out.command = rewrite_doas(cmd, use_ticket, allocator)
	case .Pkexec, .Runas, .Su, .None:
		out.command = strings.clone(cmd, allocator)
	}
	return out
}

rewrite_destroy :: proc(r: ^Rewrite) {
	if r == nil {
		return
	}
	delete(r.command)
	delete(r.sudo_askpass)
	delete(r.doas_askpass)
	r^ = {}
}

@(private)
rewrite_sudo :: proc(cmd: string, use_ticket: bool, allocator := context.allocator) -> string {
	tokens := strings.fields(cmd)
	defer delete(tokens)
	if len(tokens) == 0 {
		return strings.clone(cmd, allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	inserted_a := false
	inserted_n := false
	for tok, i in tokens {
		is_sudo := tok == "sudo" || strings.has_suffix(tok, "/sudo")
		if i > 0 {
			strings.write_byte(&b, ' ')
		}
		strings.write_string(&b, tok)
		if is_sudo {
			rest_has_A := false
			rest_has_n := false
			for t2 in tokens[i + 1:] {
				if t2 == "-A" || t2 == "--askpass" {
					rest_has_A = true
				}
				if t2 == "-n" || t2 == "--non-interactive" {
					rest_has_n = true
				}
				if len(t2) > 0 && t2[0] != '-' {
					break
				}
			}
			if use_ticket {
				if !rest_has_n && !inserted_n {
					strings.write_string(&b, " -n")
					inserted_n = true
				}
			} else if !rest_has_A && !inserted_a {
				strings.write_string(&b, " -A")
				inserted_a = true
			}
		}
	}
	s := strings.to_string(b)
	// Drop -S / --stdin from the rewritten command.
	if !strings.contains(s, " -S") && !strings.contains(s, " --stdin") {
		return s
	}
	s2, _ := strings.replace_all(s, " -S", "", context.temp_allocator)
	s3, _ := strings.replace_all(s2, " --stdin", "", context.temp_allocator)
	delete(s)
	return strings.clone(s3, allocator)
}

@(private)
rewrite_doas :: proc(cmd: string, use_ticket: bool, allocator := context.allocator) -> string {
	if !use_ticket {
		return strings.clone(cmd, allocator)
	}
	tokens := strings.fields(cmd)
	defer delete(tokens)
	if len(tokens) == 0 {
		return strings.clone(cmd, allocator)
	}
	b: strings.Builder
	strings.builder_init(&b, allocator)
	inserted_n := false
	for tok, i in tokens {
		is_doas := tok == "doas" || strings.has_suffix(tok, "/doas")
		if i > 0 {
			strings.write_byte(&b, ' ')
		}
		strings.write_string(&b, tok)
		if is_doas && !inserted_n {
			rest_has_n := false
			for t2 in tokens[i + 1:] {
				if t2 == "-n" {
					rest_has_n = true
				}
				if len(t2) > 0 && t2[0] != '-' {
					break
				}
			}
			if !rest_has_n {
				strings.write_string(&b, " -n")
				inserted_n = true
			}
		}
	}
	return strings.to_string(b)
}

env_pairs_for_rewrite :: proc(r: Rewrite, allocator := context.allocator) -> []string {
	pairs := make([dynamic]string, allocator)
	if len(r.sudo_askpass) > 0 {
		append(&pairs, fmt.aprintf("SUDO_ASKPASS=%s", r.sudo_askpass, allocator = allocator))
	}
	if len(r.doas_askpass) > 0 {
		append(&pairs, fmt.aprintf("DOAS_ASKPASS=%s", r.doas_askpass, allocator = allocator))
	}
	return pairs[:]
}
