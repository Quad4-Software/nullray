// SPDX-License-Identifier: 0BSD
/*
Approved-model policy from models.json with lock and role aliases.
*/

package subagent

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "nullray:constants"
import "nullray:sandbox"

Model_Policy :: struct {
	lock:     bool,
	default:  string,
	approved: [dynamic]string,
	aliases:  map[string]string,
	roles:    map[string]string,
	loaded:   bool,
}

g_policy: Model_Policy
g_policy_mu: sync.Mutex

policy_destroy :: proc(p: ^Model_Policy) {
	if p == nil {
		return
	}
	delete(p.default)
	for a in p.approved {
		delete(a)
	}
	delete(p.approved)
	for k, v in p.aliases {
		delete(k)
		delete(v)
	}
	delete(p.aliases)
	for k, v in p.roles {
		delete(k)
		delete(v)
	}
	delete(p.roles)
	p^ = {}
}

policy_clear_global :: proc() {
	sync.mutex_lock(&g_policy_mu)
	defer sync.mutex_unlock(&g_policy_mu)
	policy_destroy(&g_policy)
}

policy_paths :: proc(allocator := context.temp_allocator) -> (user_path: string, project_path: string) {
	cfg := sandbox.resolve_config_dir(allocator)
	user_path, _ = filepath.join({cfg, constants.MODELS_FILE}, allocator)
	ws := ""
	st := sandbox.state()
	if st != nil && len(st.workspace) > 0 {
		ws = st.workspace
	} else if cwd, err := os.get_working_directory(allocator); err == nil {
		ws = cwd
	}
	if len(ws) > 0 {
		project_path, _ = filepath.join({ws, constants.SUBAGENTS_DIR, constants.MODELS_FILE}, allocator)
	}
	return
}

policy_parse_object :: proc(p: ^Model_Policy, obj: json.Object) {
	if v, ok := obj["lock"]; ok {
		if b, bok := v.(json.Boolean); bok {
			p.lock = bool(b)
		}
	}
	if v, ok := obj["default"]; ok {
		if s, sok := v.(json.String); sok && len(s) > 0 {
			delete(p.default)
			p.default = strings.clone(string(s))
		}
	}
	if v, ok := obj["approved"]; ok {
		if arr, aok := v.(json.Array); aok {
			for item in arr {
				if s, sok := item.(json.String); sok && len(s) > 0 {
					append(&p.approved, strings.clone(string(s)))
				}
			}
		}
	}
	if v, ok := obj["aliases"]; ok {
		if m, mok := v.(json.Object); mok {
			for k, val in m {
				if s, sok := val.(json.String); sok {
					p.aliases[strings.clone(string(k))] = strings.clone(string(s))
				}
			}
		}
	}
	if v, ok := obj["roles"]; ok {
		if m, mok := v.(json.Object); mok {
			for k, val in m {
				if s, sok := val.(json.String); sok {
					p.roles[strings.clone(string(k))] = strings.clone(string(s))
				}
			}
		}
	}
}

policy_load_file :: proc(p: ^Model_Policy, path: string) -> bool {
	data, ferr := os.read_entire_file(path, context.temp_allocator)
	if ferr != nil || len(data) == 0 {
		return false
	}
	doc, err := json.parse(data, .JSON, allocator = context.temp_allocator)
	if err != nil {
		return false
	}
	obj, ook := doc.(json.Object)
	if !ook {
		return false
	}
	policy_parse_object(p, obj)
	return true
}

policy_ensure_loaded :: proc() {
	sync.mutex_lock(&g_policy_mu)
	defer sync.mutex_unlock(&g_policy_mu)
	if g_policy.loaded {
		return
	}
	g_policy.approved = make([dynamic]string)
	g_policy.aliases = make(map[string]string)
	g_policy.roles = make(map[string]string)
	user_path, project_path := policy_paths()
	_ = policy_load_file(&g_policy, user_path)
	_ = policy_load_file(&g_policy, project_path)
	if v, ok := os.lookup_env(constants.ENV_MODEL_LOCK, context.temp_allocator); ok {
		low := strings.to_lower(strings.trim_space(v), context.temp_allocator)
		if low == "1" || low == "true" || low == "on" {
			g_policy.lock = true
		} else if low == "0" || low == "false" || low == "off" {
			g_policy.lock = false
		}
	}
	g_policy.loaded = true
}

policy_reload :: proc() {
	sync.mutex_lock(&g_policy_mu)
	policy_destroy(&g_policy)
	sync.mutex_unlock(&g_policy_mu)
	policy_ensure_loaded()
}

policy_set_lock :: proc(locked: bool) {
	policy_ensure_loaded()
	sync.mutex_lock(&g_policy_mu)
	g_policy.lock = locked
	sync.mutex_unlock(&g_policy_mu)
}

policy_is_locked :: proc() -> bool {
	policy_ensure_loaded()
	sync.mutex_lock(&g_policy_mu)
	defer sync.mutex_unlock(&g_policy_mu)
	return g_policy.lock
}

policy_expand_alias :: proc(name: string, allocator := context.allocator) -> string {
	policy_ensure_loaded()
	sync.mutex_lock(&g_policy_mu)
	defer sync.mutex_unlock(&g_policy_mu)
	n := strings.trim_space(name)
	if strings.has_prefix(n, "alias:") {
		n = n[6:]
	}
	if v, ok := g_policy.aliases[n]; ok && len(v) > 0 {
		return strings.clone(v, allocator)
	}
	return strings.clone(n, allocator)
}

policy_is_approved :: proc(model: string) -> bool {
	policy_ensure_loaded()
	sync.mutex_lock(&g_policy_mu)
	defer sync.mutex_unlock(&g_policy_mu)
	if len(g_policy.approved) == 0 {
		return true
	}
	expanded := policy_expand_alias(model, context.temp_allocator)
	for a in g_policy.approved {
		ea := a
		if strings.has_prefix(a, "alias:") {
			if v, ok := g_policy.aliases[a[6:]]; ok {
				ea = v
			}
		} else if v, ok := g_policy.aliases[a]; ok {
			ea = v
		}
		if ea == expanded || a == model || a == expanded {
			return true
		}
	}
	return false
}

/*
Resolve model for a role or explicit request.
Order: session lock model, explicit if approved, role default, provider default if approved.
*/
policy_resolve :: proc(
	role: string,
	explicit: string,
	provider_default: string,
	session_locked_model: string,
	allocator := context.allocator,
) -> (model: string, err: string) {
	policy_ensure_loaded()
	if policy_is_locked() && len(session_locked_model) > 0 {
		return strings.clone(session_locked_model, allocator), ""
	}
	if len(explicit) > 0 {
		exp := policy_expand_alias(explicit, allocator)
		if !policy_is_approved(exp) {
			delete(exp)
			return "", fmt.aprintf("model not approved: %s", explicit, allocator = allocator)
		}
		return exp, ""
	}
	sync.mutex_lock(&g_policy_mu)
	role_alias := ""
	if v, ok := g_policy.roles[role]; ok {
		role_alias = v
	}
	pol_default := g_policy.default
	sync.mutex_unlock(&g_policy_mu)
	if len(role_alias) > 0 {
		exp := policy_expand_alias(role_alias, allocator)
		if policy_is_approved(exp) || len(g_policy.approved) == 0 {
			return exp, ""
		}
		delete(exp)
	}
	if len(pol_default) > 0 {
		exp := policy_expand_alias(pol_default, allocator)
		if policy_is_approved(exp) || len(g_policy.approved) == 0 {
			return exp, ""
		}
		delete(exp)
	}
	if len(provider_default) > 0 {
		if policy_is_approved(provider_default) || len(g_policy.approved) == 0 {
			return strings.clone(provider_default, allocator), ""
		}
		return "", fmt.aprintf("provider default model not approved: %s", provider_default, allocator = allocator)
	}
	return "", strings.clone("no model resolved", allocator)
}

policy_list_text :: proc(allocator := context.allocator) -> string {
	policy_ensure_loaded()
	sync.mutex_lock(&g_policy_mu)
	defer sync.mutex_unlock(&g_policy_mu)
	b: strings.Builder
	strings.builder_init(&b, allocator)
	strings.write_string(&b, "lock=")
	strings.write_string(&b, g_policy.lock ? "on" : "off")
	strings.write_string(&b, "\napproved:")
	if len(g_policy.approved) == 0 {
		strings.write_string(&b, " (any)")
	} else {
		for a in g_policy.approved {
			strings.write_string(&b, "\n  ")
			strings.write_string(&b, a)
		}
	}
	if len(g_policy.aliases) > 0 {
		strings.write_string(&b, "\naliases:")
		for k, v in g_policy.aliases {
			strings.write_string(&b, "\n  ")
			strings.write_string(&b, k)
			strings.write_string(&b, " -> ")
			strings.write_string(&b, v)
		}
	}
	if len(g_policy.roles) > 0 {
		strings.write_string(&b, "\nroles:")
		for k, v in g_policy.roles {
			strings.write_string(&b, "\n  ")
			strings.write_string(&b, k)
			strings.write_string(&b, " -> ")
			strings.write_string(&b, v)
		}
	}
	return strings.to_string(b)
}
