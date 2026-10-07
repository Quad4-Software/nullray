// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package provider

import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:testing"
import "core:time"
import "nullray:constants"

// Freeze the ensure path: a real cache under ~/.config/nullray must not
// clobber fixture-loaded maps mid-test.
@(private)
modelsdev_test_freeze :: proc() {
	os.set_env(constants.ENV_MODELSDEV, "0")
}

@(test)
test_modelsdev_parse_and_lookup :: proc(t: ^testing.T) {
	modelsdev_test_freeze()
	defer os.unset_env(constants.ENV_MODELSDEV)
	dir := os.get_env("TMPDIR", context.temp_allocator)
	if len(dir) == 0 {
		dir = "/tmp"
	}
	path, _ := filepath.join({dir, "nullray-modelsdev-test.json"}, context.temp_allocator)
	defer os.remove(path)
	fixture := `{
		"opencode": {"id": "opencode", "models": {
			"claude-sonnet-5": {"provider": {"npm": "@ai-sdk/anthropic"}, "limit": {"context": 1000000, "output": 128000}, "cost": {"input": 3, "output": 15}},
			"gpt-5.5": {"provider": {"npm": "@ai-sdk/openai"}, "limit": {"context": 400000}},
			"big-pickle": {"limit": {"context": 262144}}
		}},
		"other": {"models": {}}
	}`
	testing.expect(t, os.write_entire_file(path, transmute([]u8)fixture) == nil)

	sync.mutex_lock(&g_md_mu)
	modelsdev_clear_locked()
	modelsdev_parse_locked(path, time.now())
	sync.mutex_unlock(&g_md_mu)
	defer {
		sync.mutex_lock(&g_md_mu)
		modelsdev_clear_locked()
		sync.mutex_unlock(&g_md_mu)
	}

	testing.expect(t, g_md_loaded)
	testing.expect(t, opencode_npm_to_api(modelsdev_npm("opencode", "claude-sonnet-5")) == .Messages)
	testing.expect(t, opencode_npm_to_api(modelsdev_npm("opencode", "gpt-5.5")) == .Responses)
	testing.expect(t, opencode_npm_to_api(modelsdev_npm("opencode", "big-pickle")) == .Chat)
	testing.expect(t, modelsdev_npm("opencode", "missing-model") == "")

	meta, ok := modelsdev_model_meta("opencode", "claude-sonnet-5")
	testing.expect(t, ok)
	testing.expect_value(t, meta.context_limit, 1000000)
	testing.expect_value(t, meta.output_limit, 128000)
	testing.expect(t, meta.has_cost)
	testing.expect(t, meta.cost_in == 3 && meta.cost_out == 15)

	_, ok2 := modelsdev_model_meta("opencode", "gpt-5.5")
	testing.expect(t, ok2)
	_, ok3 := modelsdev_model_meta("opencode", "nope")
	testing.expect(t, !ok3)
}

@(test)
test_modelsdev_enrich_models :: proc(t: ^testing.T) {
	modelsdev_test_freeze()
	defer os.unset_env(constants.ENV_MODELSDEV)
	dir := os.get_env("TMPDIR", context.temp_allocator)
	if len(dir) == 0 {
		dir = "/tmp"
	}
	path, _ := filepath.join({dir, "nullray-modelsdev-test2.json"}, context.temp_allocator)
	defer os.remove(path)
	fixture := `{"opencode": {"models": {"kimi-k3": {"limit": {"context": 1048576}, "cost": {"input": 0.6, "output": 2.5}}}}}`
	testing.expect(t, os.write_entire_file(path, transmute([]u8)fixture) == nil)

	sync.mutex_lock(&g_md_mu)
	modelsdev_clear_locked()
	modelsdev_parse_locked(path, time.now())
	sync.mutex_unlock(&g_md_mu)
	defer {
		sync.mutex_lock(&g_md_mu)
		modelsdev_clear_locked()
		sync.mutex_unlock(&g_md_mu)
	}

	models := []Model_Info{{id = "kimi-k3"}, {id = "unknown"}}
	modelsdev_enrich("opencode", models)
	testing.expect_value(t, models[0].context_limit, 1048576)
	testing.expect(t, models[0].has_cost)
	testing.expect(t, models[0].cost_in == 0.6)
	testing.expect_value(t, models[1].context_limit, 0)
	testing.expect(t, !models[1].has_cost)
}

@(test)
test_modelsdev_ids_and_list :: proc(t: ^testing.T) {
	modelsdev_test_freeze()
	defer os.unset_env(constants.ENV_MODELSDEV)
	dir := os.get_env("TMPDIR", context.temp_allocator)
	if len(dir) == 0 {
		dir = "/tmp"
	}
	path, _ := filepath.join({dir, "nullray-modelsdev-test3.json"}, context.temp_allocator)
	defer os.remove(path)
	fixture := `{"google": {"models": {
		"gemini-3-pro": {"limit": {"context": 1000000}, "cost": {"input": 2, "output": 12}},
		"gemini-3-flash": {}
	}}}`
	testing.expect(t, os.write_entire_file(path, transmute([]u8)fixture) == nil)

	sync.mutex_lock(&g_md_mu)
	modelsdev_clear_locked()
	modelsdev_parse_locked(path, time.now())
	sync.mutex_unlock(&g_md_mu)
	defer {
		sync.mutex_lock(&g_md_mu)
		modelsdev_clear_locked()
		sync.mutex_unlock(&g_md_mu)
	}

	// gemini maps to the google catalog key.
	testing.expect_value(t, modelsdev_provider_id("gemini"), "google")
	testing.expect_value(t, modelsdev_provider_id("opencode"), "opencode")

	ids := modelsdev_ids("gemini", context.temp_allocator)
	testing.expect_value(t, len(ids), 2)
	testing.expect_value(t, ids[0], "gemini-3-flash")
	testing.expect_value(t, ids[1], "gemini-3-pro")

	list := modelsdev_list("gemini", context.temp_allocator)
	testing.expect_value(t, len(list), 2)
	testing.expect_value(t, list[1].id, "gemini-3-pro")
	testing.expect_value(t, list[1].context_limit, 1000000)
	testing.expect(t, list[1].has_cost)

	testing.expect(t, len(modelsdev_ids("llamacpp", context.temp_allocator)) == 0)
}
