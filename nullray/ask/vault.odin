// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Named secret vault for values the model may need but must never read
(api keys, tokens). Stored in-process only, zeroed on forget or clear.
Values can be bound to process env so providers and shell children pick
them up without entering tool results.
*/

package ask

import "core:os"
import "core:strings"
import "core:sync"
import "nullray:elevate"

g_vault_mu: sync.Mutex
g_vault: map[string]string

secret_put :: proc(name, value: string) {
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

/*
Caller owns the returned clone and should zero it when done.
*/
secret_get :: proc(name: string, allocator := context.allocator) -> string {
	sync.mutex_lock(&g_vault_mu)
	defer sync.mutex_unlock(&g_vault_mu)
	if v, ok := g_vault[name]; ok {
		return strings.clone(v, allocator)
	}
	return ""
}

secret_has :: proc(name: string) -> bool {
	sync.mutex_lock(&g_vault_mu)
	defer sync.mutex_unlock(&g_vault_mu)
	_, ok := g_vault[name]
	return ok
}

secret_forget :: proc(name: string) -> bool {
	sync.mutex_lock(&g_vault_mu)
	defer sync.mutex_unlock(&g_vault_mu)
	for k in g_vault {
		if k == name {
			old := g_vault[k]
			delete_key(&g_vault, k)
			delete(k)
			elevate.zero_and_delete(old)
			return true
		}
	}
	return false
}

secret_names :: proc(allocator := context.allocator) -> []string {
	sync.mutex_lock(&g_vault_mu)
	defer sync.mutex_unlock(&g_vault_mu)
	out := make([dynamic]string, allocator)
	for k in g_vault {
		append(&out, strings.clone(k, allocator))
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
