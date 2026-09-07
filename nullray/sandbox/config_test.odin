// SPDX-License-Identifier: 0BSD
package sandbox

import "core:testing"
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
test_config_unknown_sandbox_stays_warn :: proc(t: ^testing.T) {
	had, prev := test_env_set(constants.ENV_SANDBOX, "landlock")
	defer test_env_restore(constants.ENV_SANDBOX, had, prev)
	cfg := config_from_env()
	defer config_destroy(&cfg)
	testing.expect_value(t, cfg.mode, Mode.Warn)
}
