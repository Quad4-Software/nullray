// SPDX-License-Identifier: 0BSD
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
