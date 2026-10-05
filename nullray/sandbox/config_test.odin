// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package sandbox

import "core:testing"
import "core:strings"
import "nullray:constants"

@(test)
test_config_from_env_modes :: proc(t: ^testing.T) {
	Case :: struct {
		val:  string,
		want: Mode,
	}
	cases := []Case{
		{"off", .Off},
		{"0", .Off},
		{"soft", .Warn},
		{"warn", .Warn},
		{"strict", .Strict},
		{"on", .Strict},
		{"1", .Strict},
	}
	for c in cases {
		had, prev := test_env_set(constants.ENV_SANDBOX, c.val)
		cfg := config_from_env()
		testing.expect_value(t, cfg.mode, c.want)
		config_destroy(&cfg)
		test_env_restore(constants.ENV_SANDBOX, had, prev)
	}
}

@(test)
test_config_from_env_net_and_fs :: proc(t: ^testing.T) {
	had_n, prev_n := test_env_set(constants.ENV_SANDBOX_NET, "local")
	had_f, prev_f := test_env_set(constants.ENV_SANDBOX_FS, "ro")
	defer {
		test_env_restore(constants.ENV_SANDBOX_NET, had_n, prev_n)
		test_env_restore(constants.ENV_SANDBOX_FS, had_f, prev_f)
	}
	cfg := config_from_env()
	defer config_destroy(&cfg)
	testing.expect_value(t, cfg.net, Net_Mode.Local)
	testing.expect_value(t, cfg.fs, FS_Mode.RO)
}

@(test)
test_config_from_env_privacy_and_layers :: proc(t: ^testing.T) {
	had_p, prev_p := test_env_set(constants.ENV_PRIVACY, "off")
	had_s, prev_s := test_env_set(constants.ENV_SECCOMP, "0")
	had_l, prev_l := test_env_set(constants.ENV_LANDLOCK, "false")
	defer {
		test_env_restore(constants.ENV_PRIVACY, had_p, prev_p)
		test_env_restore(constants.ENV_SECCOMP, had_s, prev_s)
		test_env_restore(constants.ENV_LANDLOCK, had_l, prev_l)
	}
	cfg := config_from_env()
	defer config_destroy(&cfg)
	testing.expect(t, !cfg.privacy)
	testing.expect(t, !cfg.seccomp)
	testing.expect(t, !cfg.landlock)
}

@(test)
test_config_extra_paths_abs_only :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_SANDBOX_EXTRA_RW, "/tmp/nullray-extra-test,relative/nope")
	defer test_env_restore(constants.ENV_SANDBOX_EXTRA_RW, had, prev)
	had_ops, prev_ops := test_env_unset(constants.ENV_OPS)
	defer test_env_restore(constants.ENV_OPS, had_ops, prev_ops)
	cfg := config_from_env()
	defer config_destroy(&cfg)
	found := false
	for p in cfg.extra_rw {
		if p == "/tmp/nullray-extra-test" {
			found = true
		}
		testing.expectf(t, p[0] == '/', "relative slipped in: %s", p)
	}
	testing.expect(t, found)
}

@(test)
test_ops_docker_profile_adds_sock :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_OPS, "docker")
	defer test_env_restore(constants.ENV_OPS, had, prev)
	cfg := config_from_env()
	defer config_destroy(&cfg)
	testing.expect(t, cfg.keep_docker_host)
	testing.expect(t, len(cfg.extra_sock) >= 1)
	testing.expect(t, strings.contains(cfg.ops_label, "docker"))
}

@(test)
test_net_port_from_url :: proc(t: ^testing.T) {
	Case :: struct {
		url:  string,
		port: u64,
		ok:   bool,
	}
	cases := []Case{
		{"http://127.0.0.1:8080/v1", 8080, true},
		{"http://127.0.0.1:9931", 9931, true},
		{"https://api.example.com/v1", 443, true},
		{"http://localhost", 80, true},
		{"http://[::1]:9000/v1", 9000, true},
		{"127.0.0.1:8080", 8080, true},
		{"", 0, false},
		{"http://127.0.0.1:notaport/v1", 0, false},
		{"http://127.0.0.1:99999/", 0, false},
	}
	for c in cases {
		port, ok := net_port_from_url(c.url)
		testing.expectf(t, ok == c.ok, "%s: ok %v want %v", c.url, ok, c.ok)
		if ok {
			testing.expectf(t, port == c.port, "%s: port %d want %d", c.url, port, c.port)
		}
	}
}

@(test)
test_config_net_ports_from_provider_env :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_LLAMACPP_HOST, "http://127.0.0.1:9111/v1")
	had_p, prev_p := test_env_set(constants.ENV_SANDBOX_PORTS, "9333, 8080")
	defer {
		test_env_restore(constants.ENV_LLAMACPP_HOST, had, prev)
		test_env_restore(constants.ENV_SANDBOX_PORTS, had_p, prev_p)
	}
	cfg := config_from_env()
	defer config_destroy(&cfg)
	has :: proc(ports: []u64, want: u64) -> bool {
		for p in ports {
			if p == want {
				return true
			}
		}
		return false
	}
	testing.expect(t, has(cfg.net_ports[:], 9111))
	testing.expect(t, has(cfg.net_ports[:], 9333))
	testing.expect(t, has(cfg.net_ports[:], 8080))
	testing.expect(t, has(cfg.net_ports[:], 9931))
}

@(test)
test_ops_kube_blocked_without_secrets_allow :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_OPS, "kube")
	had_s, prev_s := test_env_unset(constants.ENV_SECRETS_ALLOW)
	defer {
		test_env_restore(constants.ENV_OPS, had, prev)
		test_env_restore(constants.ENV_SECRETS_ALLOW, had_s, prev_s)
	}
	cfg := config_from_env()
	defer config_destroy(&cfg)
	testing.expect(t, !cfg.keep_kubeconfig)
	testing.expect(t, strings.contains(cfg.ops_label, "kube-blocked"))
}
