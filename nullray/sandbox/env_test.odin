// SPDX-License-Identifier: 0BSD
package sandbox

import "core:os"
import "core:testing"

@(test)
test_env_keep_allowlist :: proc(t: ^testing.T) {
	keep := []string{
		"NULLRAY_SANDBOX",
		"HOME",
		"USER",
		"PATH",
		"TERM",
		"COLORTERM",
		"OPENROUTER_API_KEY",
		"OLLAMA_HOST",
		"LM_API_KEY",
		"XDG_CONFIG_HOME",
		"SSL_CERT_FILE",
		"CURL_CA_BUNDLE",
	}
	for k in keep {
		testing.expectf(t, env_keep(k), "expected keep %s", k)
	}
}

@(test)
test_env_keep_denylist :: proc(t: ^testing.T) {
	deny := []string{
		"OPENAI_API_KEY",
		"ANTHROPIC_API_KEY",
		"AWS_SECRET_ACCESS_KEY",
		"SSH_AUTH_SOCK",
		"GOOGLE_API_KEY",
		"GCP_PROJECT",
		"AZURE_CLIENT_SECRET",
		"DOCKER_HOST",
		"KUBECONFIG",
		"NPM_TOKEN",
		"NODE_OPTIONS",
		"LD_PRELOAD",
	}
	for k in deny {
		testing.expectf(t, !env_keep(k), "expected deny %s", k)
	}
}

@(test)
test_env_keep_deny_before_allow_google :: proc(t: ^testing.T) {
	testing.expect(t, !env_keep("GOOGLE_API_KEY"))
	testing.expect(t, !env_keep("GOOGLE_APPLICATION_CREDENTIALS"))
}

@(test)
test_env_keep_prefix_overmatch_current :: proc(t: ^testing.T) {
	// TERM and PATH are exact-or-prefix keeps today.
	testing.expect(t, env_keep("TERMINATOR"))
	testing.expect(t, env_keep("PATHOLOGY"))
}

@(test)
test_env_scrub_unsets_cloud_keys :: proc(t: ^testing.T) {
	probe := []string{"OPENAI_API_KEY", "ANTHROPIC_API_KEY", "AWS_ACCESS_KEY_ID"}
	saved_had: [3]bool
	saved_prev: [3]string
	for i in 0 ..< len(probe) {
		saved_had[i], saved_prev[i] = test_env_set(probe[i], "secret-value")
	}
	keep_had, keep_prev := test_env_set("OPENROUTER_API_KEY", "or-keep")
	defer {
		for i in 0 ..< len(probe) {
			test_env_restore(probe[i], saved_had[i], saved_prev[i])
		}
		test_env_restore("OPENROUTER_API_KEY", keep_had, keep_prev)
	}

	env_scrub()

	for k in probe {
		_, ok := os.lookup_env(k, context.temp_allocator)
		testing.expectf(t, !ok, "expected scrubbed %s", k)
	}
	v, ok := os.lookup_env("OPENROUTER_API_KEY", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, v, "or-keep")
}
