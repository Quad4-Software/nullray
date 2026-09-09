// SPDX-License-Identifier: 0BSD
package provider

import "core:os"
import "core:testing"
import "nullray:constants"

@(test)
test_key_cache_survives_unset :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_GROQ_KEY, "groq-secret-value")
	os.set_env(constants.ENV_API_KEY, "shared-fallback")
	defer {
		os.unset_env(constants.ENV_GROQ_KEY)
		os.unset_env(constants.ENV_API_KEY)
	}
	cache_api_keys_from_env()
	os.unset_env(constants.ENV_GROQ_KEY)
	got := lookup_api_key_env(constants.ENV_GROQ_KEY, constants.ENV_API_KEY)
	testing.expect_value(t, got, "groq-secret-value")
}
