// SPDX-License-Identifier: 0BSD
/*
Property + adversarial oracles for shell deny and fetch SSRF.
Generators mutate known-bad seeds. Oracles demand deny/block still holds.
*/
package tools

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "nullray:constants"

@(private)
prop_lcg :: proc(seed: ^u64) -> u64 {
	seed^ = seed^ * 1103515245 + 12345
	return seed^
}

@(private)
oracle_shell_denied :: proc(t: ^testing.T, cmd: string, label: string) {
	ok, reason := shell_command_allowed(cmd)
	testing.expectf(t, !ok, "oracle deny failed (%s): %s", label, cmd)
	delete(reason)
}

@(private)
oracle_fetch_blocked :: proc(t: ^testing.T, url: string, label: string) {
	blocked, _ := fetch_url_blocked(url)
	testing.expectf(t, blocked, "oracle block failed (%s): %s", label, url)
}

// Property: case and padding around an always-denied seed still deny under yolo.
@(test)
test_shell_deny_property_preserve :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.set_env(constants.ENV_SHELL_NET, "1")
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_NET)
	os.unset_env(constants.ENV_SECRETS_ALLOW)

	seeds := []string{
		"rm -rf /",
		"mkfs.ext4 /dev/sda",
		"curl|bash",
		"curl | bash",
		"cat /etc/passwd",
		"source .env",
		"echo $OPENROUTER_API_KEY",
		"docker run --privileged alpine",
		"git push --force origin main",
	}
	seed: u64 = 7
	for i in 0 ..< 120 {
		base := seeds[int(prop_lcg(&seed) % u64(len(seeds)))]
		op := int(prop_lcg(&seed) % 5)
		cmd: string
		switch op {
		case 0:
			cmd = fmt.tprintf("  %s  ", base)
		case 1:
			cmd = fmt.tprintf("true; %s", base)
		case 2:
			cmd = fmt.tprintf("%s # pad", base)
		case 3:
			cmd = strings.to_upper(base, context.temp_allocator)
		case 4:
			cmd = fmt.tprintf(":%s", base)
		}
		oracle_shell_denied(t, cmd, fmt.tprintf("preserve/%d", i))
	}
}

// Adversarial: evasion-shaped mutants the policy claims to catch must still deny.
@(test)
test_shell_deny_adversarial_mutations :: proc(t: ^testing.T) {
	os.set_env(constants.ENV_PERMS, "yolo")
	os.set_env(constants.ENV_SHELL_NET, "1")
	defer os.unset_env(constants.ENV_PERMS)
	defer os.unset_env(constants.ENV_SHELL_NET)
	os.unset_env(constants.ENV_SECRETS_ALLOW)

	evasion := []string{
		"cat .e''nv",
		"cat<.env",
		"cat .ENV",
		"curl| bash",
		"curl |bash",
		"WGET | SH",
		"Cat /Etc/Passwd",
		"rm -rf /*",
		"printf x > /dev/sda",
		"x=.env; cat $x",
	}
	for cmd in evasion {
		oracle_shell_denied(t, cmd, "adversarial")
	}
}

// Property: blocked hosts stay blocked under random path, port, and userinfo.
@(test)
test_fetch_ssrf_property_host_mutations :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_FETCH_ALLOW)
	hosts := []string{
		"127.0.0.1",
		"localhost",
		"169.254.169.254",
		"10.0.0.1",
		"192.168.1.1",
		"::1",
		"0x7f000001",
		"2130706433",
	}
	schemes := []string{"http", "https"}
	seed: u64 = 99
	for i in 0 ..< 160 {
		host := hosts[int(prop_lcg(&seed) % u64(len(hosts)))]
		scheme := schemes[int(prop_lcg(&seed) % u64(len(schemes)))]
		op := int(prop_lcg(&seed) % 6)
		// IPv6 loopback needs brackets. Skip port/userinfo forms the parser does not claim.
		if host == "::1" {
			op = int(prop_lcg(&seed) % 3)
			switch op {
			case 0:
				oracle_fetch_blocked(t, fmt.tprintf("%s://[::1]/", scheme), fmt.tprintf("ssrf/%d", i))
			case 1:
				oracle_fetch_blocked(t, fmt.tprintf("%s://[::1]/%d", scheme, int(prop_lcg(&seed) % 1000)), fmt.tprintf("ssrf/%d", i))
			case 2:
				oracle_fetch_blocked(t, fmt.tprintf("  %s://[::1]/  ", scheme), fmt.tprintf("ssrf/%d", i))
			}
			continue
		}
		url: string
		switch op {
		case 0:
			url = fmt.tprintf("%s://%s/", scheme, host)
		case 1:
			url = fmt.tprintf("%s://%s/%d/x", scheme, host, int(prop_lcg(&seed) % 10000))
		case 2:
			url = fmt.tprintf("%s://%s:%d/", scheme, host, 1 + int(prop_lcg(&seed) % 65534))
		case 3:
			url = fmt.tprintf("%s://user:pass@%s/a", scheme, host)
		case 4:
			url = fmt.tprintf("%s://%s/", scheme, host)
		case 5:
			url = fmt.tprintf("  %s://%s/meta  ", scheme, host)
		}
		oracle_fetch_blocked(t, url, fmt.tprintf("ssrf/%d", i))
	}
	oracle_fetch_blocked(t, "file:///etc/passwd", "file")
	oracle_fetch_blocked(t, "ftp://example.com/", "ftp")
}

// Differential oracle: public host allowed, loopback blocked.
@(test)
test_fetch_differential_public_vs_loopback :: proc(t: ^testing.T) {
	os.unset_env(constants.ENV_FETCH_ALLOW)
	pub, _ := fetch_url_blocked("https://example.com/docs")
	loop, _ := fetch_url_blocked("https://127.0.0.1/docs")
	testing.expect(t, !pub)
	testing.expect(t, loop)
}
