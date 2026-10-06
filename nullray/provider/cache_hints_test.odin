// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Local server cache hint tests: llama.cpp gets cache_prompt and id_slot for
KV prefix reuse, ollama gets keep_alive so the model stays resident.
*/

package provider

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
save_env :: proc(key: string) -> (saved: string, had: bool) {
	if v, ok := os.lookup_env(key, context.temp_allocator); ok {
		return strings.clone(v), true
	}
	return "", false
}

@(private)
restore_env :: proc(key, saved: string, had: bool) {
	if had {
		os.set_env(key, saved)
	} else {
		os.unset_env(key)
	}
	delete(saved)
}

@test
test_llamacpp_emits_cache_prompt_no_id_slot :: proc(t: ^testing.T) {
	saved, had := save_env(constants.ENV_LOCAL_PROBE)
	defer restore_env(constants.ENV_LOCAL_PROBE, saved, had)
	os.set_env(constants.ENV_LOCAL_PROBE, "0")

	p := make_llamacpp("http://127.0.0.1:8080/v1", "", "local")
	defer provider_destroy(&p)
	msgs := []Message{{role = .User, content = "hi"}}
	body := build_openai_chat_body(&p, Chat_Request{messages = msgs}, "local", false, nil)
	testing.expect(t, strings.contains(body, `"cache_prompt":true`))
	// A pinned id_slot would serialize concurrent agents onto one KV slot.
	testing.expect(t, !strings.contains(body, "id_slot"))
	testing.expect(t, !strings.contains(body, "keep_alive"))
}

@test
test_ollama_emits_keep_alive_default :: proc(t: ^testing.T) {
	saved, had := save_env(constants.ENV_LOCAL_PROBE)
	defer restore_env(constants.ENV_LOCAL_PROBE, saved, had)
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	ka_saved, ka_had := save_env(constants.ENV_OLLAMA_KEEP_ALIVE)
	defer restore_env(constants.ENV_OLLAMA_KEEP_ALIVE, ka_saved, ka_had)
	os.unset_env(constants.ENV_OLLAMA_KEEP_ALIVE)

	p := make_ollama("http://127.0.0.1:11434", "", "m")
	defer provider_destroy(&p)
	p.caps.probed = true
	p.caps.probed_model = strings.clone("m")
	msgs := []Message{{role = .User, content = "hi"}}
	body := build_openai_chat_body(&p, Chat_Request{messages = msgs}, "m", false, nil)
	testing.expect(t, strings.contains(body, `"keep_alive":"30m"`))
}

@test
test_ollama_keep_alive_env_override_and_disable :: proc(t: ^testing.T) {
	saved, had := save_env(constants.ENV_LOCAL_PROBE)
	defer restore_env(constants.ENV_LOCAL_PROBE, saved, had)
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	ka_saved, ka_had := save_env(constants.ENV_OLLAMA_KEEP_ALIVE)
	defer restore_env(constants.ENV_OLLAMA_KEEP_ALIVE, ka_saved, ka_had)

	p := make_ollama("http://127.0.0.1:11434", "", "m")
	defer provider_destroy(&p)
	p.caps.probed = true
	p.caps.probed_model = strings.clone("m")
	msgs := []Message{{role = .User, content = "hi"}}

	os.set_env(constants.ENV_OLLAMA_KEEP_ALIVE, "2h")
	body := build_openai_chat_body(&p, Chat_Request{messages = msgs}, "m", false, nil)
	testing.expect(t, strings.contains(body, `"keep_alive":"2h"`))

	os.set_env(constants.ENV_OLLAMA_KEEP_ALIVE, "0")
	body2 := build_openai_chat_body(&p, Chat_Request{messages = msgs}, "m", false, nil)
	testing.expect(t, !strings.contains(body2, "keep_alive"))
}

@test
test_non_local_provider_emits_no_cache_hints :: proc(t: ^testing.T) {
	saved, had := save_env(constants.ENV_LOCAL_PROBE)
	defer restore_env(constants.ENV_LOCAL_PROBE, saved, had)
	os.set_env(constants.ENV_LOCAL_PROBE, "0")

	p := Provider{id = "openai", base_url = strings.clone("http://127.0.0.1:1")}
	defer provider_destroy(&p)
	msgs := []Message{{role = .User, content = "hi"}}
	body := build_openai_chat_body(&p, Chat_Request{messages = msgs}, "m", false, nil)
	testing.expect(t, !strings.contains(body, "cache_prompt"))
	testing.expect(t, !strings.contains(body, "id_slot"))
	testing.expect(t, !strings.contains(body, "keep_alive"))
}
