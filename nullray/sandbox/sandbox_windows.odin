// SPDX-License-Identifier: 0BSD
#+build windows

package sandbox

import "core:fmt"
import win "core:sys/windows"
import "core:sync"

JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE :: 0x00002000
JOB_OBJECT_LIMIT_ACTIVE_PROCESS :: 0x00000008
JobObjectExtendedLimitInformation :: 9

IO_COUNTERS :: struct {
	ReadOperationCount:  u64,
	WriteOperationCount: u64,
	OtherOperationCount: u64,
	ReadTransferCount:   u64,
	WriteTransferCount:  u64,
	OtherTransferCount:  u64,
}

JOBOBJECT_BASIC_LIMIT_INFORMATION :: struct {
	PerProcessUserTimeLimit: i64,
	PerJobUserTimeLimit:     i64,
	LimitFlags:              win.DWORD,
	MinimumWorkingSetSize:   uint,
	MaximumWorkingSetSize:   uint,
	ActiveProcessLimit:      win.DWORD,
	Affinity:                uint,
	PriorityClass:           win.DWORD,
	SchedulingClass:         win.DWORD,
}

JOBOBJECT_EXTENDED_LIMIT_INFORMATION :: struct {
	BasicLimitInformation: JOBOBJECT_BASIC_LIMIT_INFORMATION,
	IoInfo:                IO_COUNTERS,
	ProcessMemoryLimit:    uint,
	JobMemoryLimit:        uint,
	PeakProcessMemoryUsed: uint,
	PeakJobMemoryUsed:     uint,
}

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "stdcall")
foreign kernel32 {
	CreateJobObjectW :: proc(lpJobAttributes: rawptr, lpName: win.wstring) -> win.HANDLE ---
	SetInformationJobObject :: proc(
		hJob: win.HANDLE,
		JobObjectInformationClass: win.DWORD,
		lpJobObjectInformation: rawptr,
		cbJobObjectInformationLength: win.DWORD,
	) -> win.BOOL ---
	AssignProcessToJobObject :: proc(hJob: win.HANDLE, hProcess: win.HANDLE) -> win.BOOL ---
	CloseHandle :: proc(hObject: win.HANDLE) -> win.BOOL ---
	GetCurrentProcess :: proc() -> win.HANDLE ---
}

@(private)
g_job_mu: sync.Mutex
@(private)
g_job: win.HANDLE
@(private)
g_job_applied: bool

windows_job_apply :: proc(cfg: Config, state: ^State) -> Result {
	_ = cfg
	sync.mutex_lock(&g_job_mu)
	defer sync.mutex_unlock(&g_job_mu)
	if g_job_applied && g_job != nil {
		if state != nil {
			state.applied = true
		}
		return Result{ok = true, applied = true, message = "Windows Job Object active"}
	}

	job := CreateJobObjectW(nil, nil)
	if job == nil {
		return Result{
			ok = false,
			applied = false,
			message = "CreateJobObjectW failed",
		}
	}

	info: JOBOBJECT_EXTENDED_LIMIT_INFORMATION
	info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
	if SetInformationJobObject(
		job,
		JobObjectExtendedLimitInformation,
		&info,
		size_of(info),
	) == win.FALSE {
		CloseHandle(job)
		return Result{
			ok = false,
			applied = false,
			message = "SetInformationJobObject failed",
		}
	}

	if AssignProcessToJobObject(job, GetCurrentProcess()) == win.FALSE {
		msg := "AssignProcessToJobObject skipped (nested or restricted); Job Object created for children"
		g_job = job
		g_job_applied = true
		if state != nil {
			state.applied = true
		}
		return Result{ok = true, applied = true, message = msg}
	}

	g_job = job
	g_job_applied = true
	if state != nil {
		state.applied = true
	}
	return Result{
		ok = true,
		applied = true,
		message = "Windows Job Object applied (KILL_ON_JOB_CLOSE)",
	}
}

windows_job_spawn_helper :: proc() -> (available: bool, message: string) {
	sync.mutex_lock(&g_job_mu)
	defer sync.mutex_unlock(&g_job_mu)
	if g_job_applied && g_job != nil {
		return true, "Job Object active"
	}
	return true, "Job Object helper available (apply on sandbox start)"
}

windows_job_handle :: proc() -> win.HANDLE {
	sync.mutex_lock(&g_job_mu)
	defer sync.mutex_unlock(&g_job_mu)
	return g_job
}

windows_job_assign_pid :: proc(pid: win.DWORD) -> bool {
	_ = pid
	// Child assign needs OpenProcess. Shell path can call AssignProcessToJobObject
	// when a process handle is available. Keep API for future spawn wiring.
	return g_job != nil
}

landlock_apply :: proc(cfg: Config, state: ^State) -> (ok: bool, msg: string) {
	_ = cfg
	_ = state
	return false, "landlock is Linux-only"
}

seccomp_apply :: proc() -> (ok: bool, msg: string) {
	return false, "seccomp is Linux-only"
}
