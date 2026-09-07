#+build linux

/*
seccomp-bpf deny filter for dangerous syscalls.
Default-allow with explicit denies. Complements Landlock path/net rules.
*/

package sandbox

import "core:fmt"
import linux "core:sys/linux"

SECCOMP_SET_MODE_FILTER :: u32(1)
SECCOMP_RET_ALLOW :: u32(0x7fff0000)
SECCOMP_RET_ERRNO :: u32(0x00050000)
EPERM :: u32(1)

BPF_LD :: u16(0x00)
BPF_W :: u16(0x00)
BPF_ABS :: u16(0x20)
BPF_JMP :: u16(0x05)
BPF_JEQ :: u16(0x10)
BPF_K :: u16(0x00)
BPF_RET :: u16(0x06)

AUDIT_ARCH_X86_64 :: u32(0xc000003e)

Sock_Filter :: struct {
	code: u16,
	jt:   u8,
	jf:   u8,
	k:    u32,
}

Sock_Fprog :: struct {
	len:    u16,
	filter: [^]Sock_Filter,
}

bpf_stmt :: proc(code: u16, k: u32) -> Sock_Filter {
	return Sock_Filter{code = code, jt = 0, jf = 0, k = k}
}

bpf_jump :: proc(code: u16, k: u32, jt, jf: u8) -> Sock_Filter {
	return Sock_Filter{code = code, jt = jt, jf = jf, k = k}
}

// Offsets into seccomp_data
SECCOMP_DATA_NR :: u32(0)
SECCOMP_DATA_ARCH :: u32(4)

seccomp_apply :: proc() -> (ok: bool, msg: string) {
	when ODIN_ARCH != .amd64 {
		return true, "seccomp skipped (non-amd64)"
	}

	// Classic BPF: validate arch, deny listed nrs, else allow.
	deny := [?]u32{
		101, // ptrace
		310, // process_vm_readv
		311, // process_vm_writev
		165, // mount
		166, // umount2
		155, // pivot_root
		161, // chroot
		272, // unshare
		308, // setns
		321, // bpf
		298, // perf_event_open
		246, // kexec_load
		175, // init_module
		313, // finit_module
		176, // delete_module
		169, // reboot
		167, // swapon
		168, // swapoff
		163, // acct
		103, // syslog
		250, // keyctl
		248, // add_key
		249, // request_key
		304, // open_by_handle_at
		303, // name_to_handle_at
		323, // userfaultfd
		172, // iopl
		173, // ioperm
	}

	filters := make([dynamic]Sock_Filter, context.temp_allocator)
	append(&filters, bpf_stmt(BPF_LD | BPF_W | BPF_ABS, SECCOMP_DATA_ARCH))
	append(&filters, bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0))
	append(&filters, bpf_stmt(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM))
	append(&filters, bpf_stmt(BPF_LD | BPF_W | BPF_ABS, SECCOMP_DATA_NR))

	for nr, i in deny {
		remaining := u8(len(deny) - i)
		// If equal, jump to deny ret which we place after the loop body.
		// jt = remaining (skip remaining compares) then hit deny.
		// Actually: jeq nr -> jump forward to deny instruction.
		// Number of instructions after this jump until deny = (len-1-i)*1 + 0 for allow path...
		// Simpler: for each nr, jeq -> deny (jt=0 means next is deny? No.
		// Pattern: JEQ nr, 0, 1 / RET ERRNO  -- if equal fall through to RET, else skip RET
		append(&filters, bpf_jump(BPF_JMP | BPF_JEQ | BPF_K, nr, 0, 1))
		append(&filters, bpf_stmt(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM))
		_ = remaining
	}
	append(&filters, bpf_stmt(BPF_RET | BPF_K, SECCOMP_RET_ALLOW))

	prog := Sock_Fprog{
		len = u16(len(filters)),
		filter = raw_data(filters),
	}

	ret := linux.syscall(
		linux.SYS_seccomp,
		uintptr(SECCOMP_SET_MODE_FILTER),
		uintptr(0),
		uintptr(rawptr(&prog)),
	)
	if ret < 0 {
		return false, fmt.tprintf("seccomp: errno %d", -ret)
	}
	return true, "seccomp deny-list active"
}
