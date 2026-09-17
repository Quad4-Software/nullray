// SPDX-License-Identifier: 0BSD
/*
Tests for saved provider/model precedence against explicit env config.
*/

package session

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"
import "nullray:provider"

saved_model_test_session :: proc(provider_id, model: string) -> (s: Session) {
	s.provider_id = strings.clone(provider_id)
	s.model = strings.clone(model)
	return s
}

saved_model_test_session_destroy :: proc(s: ^Session) {
	delete(s.provider_id)
	delete(s.model)
	s^ = {}
}

@(test)
test_apply_saved_model_no_env :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_PROVIDER)
	defer os.unset_env(constants.ENV_PROVIDER)
	os.unset_env(constants.ENV_MODEL)
	defer os.unset_env(constants.ENV_MODEL)
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	defer os.unset_env(constants.ENV_LOCAL_PROBE)

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)
	provider.registry_set_active(&reg, "openai")

	s := saved_model_test_session("openrouter", "saved/model")
	defer saved_model_test_session_destroy(&s)

	testing.expect(t, session_apply_saved_model(&s, &reg))
	p := provider.registry_active(&reg)
	testing.expect(t, p != nil)
	testing.expect_value(t, p.id, "openrouter")
	testing.expect_value(t, p.default_model, "saved/model")
}

@(test)
test_apply_saved_model_env_wins :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PROVIDER, "openai")
	defer os.unset_env(constants.ENV_PROVIDER)
	os.set_env(constants.ENV_MODEL, "env/model")
	defer os.unset_env(constants.ENV_MODEL)

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)

	s := saved_model_test_session("openrouter", "saved/model")
	defer saved_model_test_session_destroy(&s)

	testing.expect(t, !session_apply_saved_model(&s, &reg))
	p := provider.registry_active(&reg)
	testing.expect(t, p != nil)
	testing.expect_value(t, p.id, "openai")
	testing.expect_value(t, p.default_model, "env/model")
}

@(test)
test_apply_saved_model_env_model_follows_saved_provider :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_PROVIDER)
	defer os.unset_env(constants.ENV_PROVIDER)
	os.set_env(constants.ENV_MODEL, "env/model")
	defer os.unset_env(constants.ENV_MODEL)
	os.set_env(constants.ENV_LOCAL_PROBE, "0")
	defer os.unset_env(constants.ENV_LOCAL_PROBE)

	reg: provider.Registry
	provider.registry_init(&reg)
	defer provider.registry_destroy(&reg)

	s := saved_model_test_session("openrouter", "saved/model")
	defer saved_model_test_session_destroy(&s)

	testing.expect(t, session_apply_saved_model(&s, &reg))
	p := provider.registry_active(&reg)
	testing.expect(t, p != nil)
	testing.expect_value(t, p.id, "openrouter")
	testing.expect_value(t, p.default_model, "env/model")
}
