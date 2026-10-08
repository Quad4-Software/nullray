// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package app

import "core:os"
import "core:testing"
import "nullray:ask"

@(test)
test_secret_parse_set_args :: proc(t: ^testing.T) {
	n, v := secret_parse_set_args("OPENROUTER_API_KEY=sk-test")
	testing.expect_value(t, n, "OPENROUTER_API_KEY")
	testing.expect_value(t, v, "sk-test")
	n2, v2 := secret_parse_set_args("FOO bar baz")
	testing.expect_value(t, n2, "FOO")
	testing.expect_value(t, v2, "bar baz")
	n3, v3 := secret_parse_set_args("ONLYNAME")
	testing.expect_value(t, n3, "ONLYNAME")
	testing.expect_value(t, v3, "")
}

@(test)
test_app_secret_store_hides_value_from_names :: proc(t: ^testing.T) {
	ask.secrets_clear()
	defer ask.secrets_clear()
	app_secret_store("UNIT_TEST_SECRET", "super-value-never-list")
	testing.expect(t, ask.secret_has("UNIT_TEST_SECRET"))
	names := ask.secret_names(context.temp_allocator)
	found := false
	for n in names {
		if n == "UNIT_TEST_SECRET" {
			found = true
		}
		testing.expect(t, n != "super-value-never-list")
	}
	testing.expect(t, found)
	envv, ok := os.lookup_env("UNIT_TEST_SECRET", context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, envv, "super-value-never-list")
	os.unset_env("UNIT_TEST_SECRET")
}
