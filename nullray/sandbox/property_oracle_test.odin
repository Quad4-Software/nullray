// SPDX-License-Identifier: 0BSD
/*
Property + adversarial oracles for path_beneath and secret path policy.
*/
package sandbox

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
sprop_lcg :: proc(seed: ^u64) -> u64 {
	seed^ = seed^ * 1103515245 + 12345
	return seed^
}

// Property: random children under root are beneath. Sibling prefix is not.
@(test)
test_path_beneath_property_children_vs_sibling :: proc(t: ^testing.T) {
	root := "/tmp/nullray-ws"
	seed: u64 = 11
	for i in 0 ..< 100 {
		depth := 1 + int(sprop_lcg(&seed) % 4)
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		strings.write_string(&b, root)
		for _ in 0 ..< depth {
			seg := fmt.tprintf("s%d", int(sprop_lcg(&seed) % 1000))
			strings.write_byte(&b, '/')
			strings.write_string(&b, seg)
		}
		child := strings.to_string(b)
		testing.expectf(t, path_beneath(child, root), "child beneath failed/%d: %s", i, child)
		root_slash := fmt.tprintf("%s/", root)
		testing.expectf(t, path_beneath(child, root_slash), "slash root/%d", i)

		sib := fmt.tprintf("%s_evil/%d", root, int(sprop_lcg(&seed) % 50))
		testing.expectf(t, !path_beneath(sib, root), "sibling leak/%d: %s", i, sib)
	}
	testing.expect(t, path_beneath(root, root))
	testing.expect(t, !path_beneath("/tmp/nullray-ws2", root))
}

// Property: secret basenames under random prefixes stay blocked.
@(test)
test_secret_basename_property_random_prefix :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	bases := SECRET_BASENAMES
	sufs := SECRET_SUFFIXES
	seed: u64 = 23
	for i in 0 ..< 120 {
		name := bases[int(sprop_lcg(&seed) % u64(len(bases)))]
		depth := 1 + int(sprop_lcg(&seed) % 3)
		b: strings.Builder
		strings.builder_init(&b, context.temp_allocator)
		strings.write_string(&b, "/tmp/proj")
		for _ in 0 ..< depth {
			strings.write_string(&b, fmt.tprintf("/d%d", int(sprop_lcg(&seed) % 200)))
		}
		strings.write_byte(&b, '/')
		strings.write_string(&b, name)
		path := strings.to_string(b)
		testing.expectf(t, path_is_secret_blocked(path), "secret property/%d: %s", i, path)
	}
	for suf in sufs {
		p := fmt.tprintf("/tmp/proj/app%s", suf)
		testing.expectf(t, path_is_secret_blocked(p), "suffix property: %s", p)
	}
}

// Adversarial: traversal-cleaned secret paths and shell mention mutants stay blocked.
@(test)
test_secret_adversarial_traversal_and_shell :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	trav := []string{
		"/tmp/ws/a/../../.ssh/id_rsa",
		"/tmp/ws/./.env",
		"/tmp/ws/sub/../.env.local",
		"/tmp/ws/x/../../../home/u/.aws/credentials",
	}
	for p in trav {
		clean, _ := filepath.clean(p, context.temp_allocator)
		testing.expectf(t, path_is_secret_blocked(p), "raw trav: %s", p)
		testing.expectf(t, path_is_secret_blocked(clean), "clean trav: %s", clean)
	}

	shells := []string{
		"cat .env",
		"cat .e''nv",
		"cat<.env",
		"source .env.production",
		"install -m 600 id_ed25519 /tmp/x",
		"cp secrets.yaml /tmp/",
	}
	for cmd in shells {
		blocked, _ := shell_mentions_secret(cmd)
		testing.expectf(t, blocked, "shell secret adversarial: %s", cmd)
	}
}

// Differential + path allow oracle: RW child ok, secret child denied, outside denied.
@(test)
test_path_allowed_oracle_rw_secret_outside :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_SECRETS_ALLOW)
	s := test_state_with_allows({"/tmp/ws"}, {"/usr"}, true)
	defer state_destroy(&s)
	seed: u64 = 41
	for i in 0 ..< 40 {
		child := fmt.tprintf("/tmp/ws/f%d.odin", int(sprop_lcg(&seed) % 500))
		testing.expectf(t, path_allowed(&s, child, true), "rw child/%d", i)
		sec := fmt.tprintf("/tmp/ws/.env.%d", int(sprop_lcg(&seed) % 9))
		// .env.N may not match basename list; also try fixed secret.
		_ = sec
		testing.expect(t, !path_allowed(&s, "/tmp/ws/.env", false))
		out := fmt.tprintf("/tmp/other/%d", int(sprop_lcg(&seed) % 50))
		testing.expectf(t, !path_allowed(&s, out, false), "outside/%d", i)
	}
	testing.expect(t, path_allowed(&s, "/usr/bin/ls", false))
	testing.expect(t, !path_allowed(&s, "/usr/bin/ls", true))
}
