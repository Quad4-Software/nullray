// SPDX-License-Identifier: 0BSD
#+build windows
/*
Windows elevate via UAC consent (no password in nullray).
*/

package elevate

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/windows"
import "nullray:constants"

broker_available :: proc() -> bool {
	return false
}

broker_start :: proc(self_exe: string) -> bool {
	_ = self_exe
	return false
}

broker_stop :: proc() {}

broker_run :: proc(
	cmd: string,
	cwd: string,
	sudo_askpass: string,
	doas_askpass: string,
	allocator := context.allocator,
) -> Result {
	_ = sudo_askpass
	_ = doas_askpass
	return run_elevated_windows(cmd, cwd, .Runas, allocator)
}

run_elevate_broker_server :: proc(sock_path: string) -> int {
	_ = sock_path
	return 1
}

run_elevated_windows :: proc(
	cmd: string,
	cwd: string,
	backend: Backend,
	allocator := context.allocator,
) -> Result {
	_ = backend
	mode := elevate_mode_from_env()
	if mode == .Deny {
		return Result{
			kind = .Denied_Shell,
			outcome = .Denied,
			backend = .Runas,
			err = strings.clone("elevation disabled", allocator),
			exit_code = 1,
		}
	}
	if headless() {
		return Result{
			kind = .Needs_Tty,
			outcome = .Needs_Tty,
			backend = .Runas,
			err = strings.clone("elevation_needs_tty: UAC requires interactive session", allocator),
			exit_code = 1,
		}
	}

	if secret_ui_enabled() {
		_, ok, cancelled := request_password(
			"Approve UAC elevation (system dialog collects credentials):",
			cmd,
			modal_secs_from_env(),
			context.temp_allocator,
		)
		if cancelled || !ok {
			circuit_record_failure()
			return Result{
				backend = .Runas,
				outcome = .Cancelled,
				kind = .Auth_Cancelled,
				exit_code = 1,
				err = strings.clone("auth_cancelled", allocator),
			}
		}
	}

	verb := windows.L("runas")
	file := windows.L("cmd.exe")
	param_s := fmt.tprintf("/C %s", cmd)
	params := windows.utf8_to_wstring(param_s)
	dir_w: windows.wstring
	if len(cwd) > 0 {
		dir_w = windows.utf8_to_wstring(cwd)
	}

	sei: windows.SHELLEXECUTEINFOW
	sei.cbSize = size_of(sei)
	sei.fMask = windows.SEE_MASK_NOCLOSEPROCESS
	sei.lpVerb = windows.wstring(verb)
	sei.lpFile = windows.wstring(file)
	sei.lpParameters = params
	sei.lpDirectory = dir_w
	sei.nShow = windows.SW_HIDE

	if windows.ShellExecuteExW(&sei) == false {
		circuit_record_failure()
		return Result{
			backend = .Runas,
			outcome = .Cancelled,
			kind = .Auth_Cancelled,
			exit_code = 1,
			err = strings.clone("UAC elevation cancelled or failed", allocator),
		}
	}
	if sei.hProcess != nil {
		_ = windows.WaitForSingleObject(sei.hProcess, u32(constants.SHELL_TIMEOUT_MS))
		code: windows.DWORD
		_ = windows.GetExitCodeProcess(sei.hProcess, &code)
		_ = windows.CloseHandle(sei.hProcess)
		circuit_record_success()
		return Result{
			backend = .Runas,
			outcome = .Askpass,
			kind = .Ok,
			exit_code = int(code),
		}
	}
	circuit_record_success()
	return Result{
		backend = .Runas,
		outcome = .Askpass,
		kind = .Ok,
		exit_code = 0,
	}
}
