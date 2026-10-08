// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package ask

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:elevate"

@(test)
test_vault_backend_memory_forced :: proc(t: ^testing.T) {
	// Force memory so unit tests never require a session bus.
	prev, had := os.lookup_env(constants.ENV_VAULT_BACKEND, context.temp_allocator)
	os.set_env(constants.ENV_VAULT_BACKEND, "memory")
	defer {
		if had {
			os.set_env(constants.ENV_VAULT_BACKEND, prev)
		} else {
			os.unset_env(constants.ENV_VAULT_BACKEND)
		}
	}
	// Reset once state by using a fresh process is ideal; here we only check
	// env parsing helper which does not need once.
	testing.expect_value(t, vault_backend_from_env(), Vault_Backend.Memory)
	testing.expect_value(t, vault_backend_from_env_when("keyring"), Vault_Backend.Keyring)
	testing.expect_value(t, vault_backend_from_env_when("auto"), Vault_Backend.Auto)
}

@(private)
vault_backend_from_env_when :: proc(v: string) -> Vault_Backend {
	os.set_env(constants.ENV_VAULT_BACKEND, v)
	return vault_backend_from_env()
}

@(test)
test_keyring_roundtrip_if_available :: proc(t: ^testing.T) {
	prev_b, had_b := os.lookup_env(constants.ENV_VAULT_BACKEND, context.temp_allocator)
	prev_s, had_s := os.lookup_env(constants.ENV_KEYRING_SERVICE, context.temp_allocator)
	os.set_env(constants.ENV_VAULT_BACKEND, "keyring")
	os.set_env(constants.ENV_KEYRING_SERVICE, "nullray-test")
	// Reset detection so this test picks up env (once may already have fired).
	// Directly call tool path without relying on global once when missing tool.
	tool := keyring_find_tool()
	if len(tool) == 0 {
		// No secret-tool on this host: skip by succeeding with note path.
		testing.expect(t, true)
		if had_b {
			os.set_env(constants.ENV_VAULT_BACKEND, prev_b)
		} else {
			os.unset_env(constants.ENV_VAULT_BACKEND)
		}
		if had_s {
			os.set_env(constants.ENV_KEYRING_SERVICE, prev_s)
		} else {
			os.unset_env(constants.ENV_KEYRING_SERVICE)
		}
		return
	}
	// Force tool globals for this process.
	g_backend = .Keyring
	g_keyring_ok = true
	g_keyring_tool = tool

	name := "NR_UNIT_KEYRING"
	val := "unit-secret-value-xyz"
	_ = keyring_clear(name)
	ok := keyring_store(name, val)
	testing.expect(t, ok)
	got, gok := keyring_lookup(name, context.allocator)
	testing.expect(t, gok)
	if gok {
		testing.expect_value(t, got, val)
		elevate.zero_and_delete(got)
	}
	// List is best-effort; store+lookup is the contract that matters.
	names := keyring_list_names(context.allocator)
	if len(names) > 0 {
		found := false
		for n in names {
			if n == name {
				found = true
			}
			delete(n)
		}
		testing.expect(t, found)
	}
	delete(names)
	testing.expect(t, keyring_clear(name))
	_, miss := keyring_lookup(name, context.allocator)
	testing.expect(t, !miss)

	if had_b {
		os.set_env(constants.ENV_VAULT_BACKEND, prev_b)
	} else {
		os.unset_env(constants.ENV_VAULT_BACKEND)
	}
	if had_s {
		os.set_env(constants.ENV_KEYRING_SERVICE, prev_s)
	} else {
		os.unset_env(constants.ENV_KEYRING_SERVICE)
	}
}

@(test)
test_secret_put_memory_backend_no_leak_names :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_VAULT_BACKEND, "memory")
	g_backend = .Memory
	g_keyring_ok = false
	secrets_clear()
	defer secrets_clear()
	secret_put("MEM_ONLY", "hidden-val")
	testing.expect(t, secret_has("MEM_ONLY"))
	names := secret_names(context.temp_allocator)
	for n in names {
		testing.expect(t, n != "hidden-val")
	}
	v := secret_get("MEM_ONLY")
	testing.expect_value(t, v, "hidden-val")
	elevate.zero_and_delete(v)
}
