// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Named secret vault for values the model may need but must never read
(api keys, tokens). In-process map always; optional FreeDesktop keyring
mirror when NULLRAY_VAULT_BACKEND=keyring|auto and secret-tool works.
Values can be bound to process env so providers and shell children pick
them up without entering tool results.
*/

package ask

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "nullray:elevate"

g_vault_mu: sync.Mutex
g_vault: map[string]string

secret_put :: proc(name, value: string) {
	sync.mutex_lock(&g_vault_mu)
	if g_vault == nil {
		g_vault = make(map[string]string)
	}
	found := false
	for k in g_vault {
		if k == name {
			old := g_vault[k]
			g_vault[k] = strings.clone(value)
			elevate.zero_and_delete(old)
			found = true
			break
		}
	}
	if !found {
		g_vault[strings.clone(name)] = strings.clone(value)
	}
	sync.mutex_unlock(&g_vault_mu)
	// Best-effort durable mirror. Never blocks agents on keyring UI long-term
	// beyond secret-tool timeout inside keyring_run.
	_ = keyring_store(name, value)
}

/*
Caller owns the returned clone and should zero it when done.
*/
secret_get :: proc(name: string, allocator := context.allocator) -> string {
	sync.mutex_lock(&g_vault_mu)
	if v, ok := g_vault[name]; ok {
		out := strings.clone(v, allocator)
		sync.mutex_unlock(&g_vault_mu)
		return out
	}
	sync.mutex_unlock(&g_vault_mu)
	// Cache miss: optional keyring load into memory for the session.
	if kv, ok := keyring_lookup(name, context.allocator); ok {
		// Re-enter put path without recursive keyring write thrash: memory only.
		secret_put_memory_only(name, kv)
		return kv
	}
	return ""
}

// Memory-only put (no keyring write). Used when hydrating from keyring.
@(private)
secret_put_memory_only :: proc(name, value: string) {
	sync.mutex_lock(&g_vault_mu)
	defer sync.mutex_unlock(&g_vault_mu)
	if g_vault == nil {
		g_vault = make(map[string]string)
	}
	for k in g_vault {
		if k == name {
			old := g_vault[k]
			g_vault[k] = strings.clone(value)
			elevate.zero_and_delete(old)
			return
		}
	}
	g_vault[strings.clone(name)] = strings.clone(value)
}

secret_has :: proc(name: string) -> bool {
	sync.mutex_lock(&g_vault_mu)
	_, ok := g_vault[name]
	sync.mutex_unlock(&g_vault_mu)
	if ok {
		return true
	}
	// Cheap probe via lookup (value discarded).
	if v, kok := keyring_lookup(name, context.allocator); kok {
		secret_put_memory_only(name, v)
		elevate.zero_and_delete(v)
		return true
	}
	return false
}

secret_forget :: proc(name: string) -> bool {
	found := false
	sync.mutex_lock(&g_vault_mu)
	for k in g_vault {
		if k == name {
			old := g_vault[k]
			delete_key(&g_vault, k)
			delete(k)
			elevate.zero_and_delete(old)
			found = true
			break
		}
	}
	sync.mutex_unlock(&g_vault_mu)
	kr := keyring_clear(name)
	return found || kr
}

secret_names :: proc(allocator := context.allocator) -> []string {
	sync.mutex_lock(&g_vault_mu)
	out := make([dynamic]string, allocator)
	seen: map[string]bool
	seen = make(map[string]bool, context.temp_allocator)
	for k in g_vault {
		append(&out, strings.clone(k, allocator))
		seen[k] = true
	}
	sync.mutex_unlock(&g_vault_mu)
	for n in keyring_list_names(context.temp_allocator) {
		if !seen[n] {
			append(&out, strings.clone(n, allocator))
			seen[n] = true
		}
	}
	return out[:]
}

/*
Copy a stored secret into the process environment under its name so
provider lookups and spawned tools see it. Does not log or return it.
*/
secret_bind_env :: proc(name: string) -> bool {
	v := secret_get(name, context.allocator)
	if len(v) == 0 {
		return false
	}
	os.set_env(name, v)
	elevate.zero_and_delete(v)
	return true
}

secrets_clear :: proc() {
	sync.mutex_lock(&g_vault_mu)
	defer sync.mutex_unlock(&g_vault_mu)
	for k, v in g_vault {
		delete(k)
		elevate.zero_and_delete(v)
	}
	delete(g_vault)
	g_vault = nil
}

/*
Append NAME=value pairs for every vault entry onto an env list (caller owns).
Used when NULLRAY_VAULT_EXPORT is on so shell/script children can read secrets
without them ever appearing in tool JSON.
*/
secret_export_env_pairs :: proc(dst: ^[dynamic]string, allocator := context.allocator) -> int {
	if dst == nil {
		return 0
	}
	sync.mutex_lock(&g_vault_mu)
	defer sync.mutex_unlock(&g_vault_mu)
	n := 0
	for k, v in g_vault {
		if len(k) == 0 || len(v) == 0 {
			continue
		}
		pair := fmt.aprintf("%s=%s", k, v, allocator = allocator)
		append(dst, pair)
		n += 1
	}
	return n
}
