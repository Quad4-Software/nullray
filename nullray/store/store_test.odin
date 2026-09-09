// SPDX-License-Identifier: 0BSD
package store

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:testing"
import "nullray:provider"

@(test)
test_sanitize_name :: proc(t: ^testing.T) {
	testing.expect_value(t, sanitize_name("ok_Name-1"), "ok_Name-1")
	testing.expect_value(t, sanitize_name("a/b c"), "a_b_c")
	testing.expect_value(t, sanitize_name(""), "default")
}

@(test)
test_sanitize_name_adversarial :: proc(t: ^testing.T) {
	testing.expect_value(t, sanitize_name("../etc/passwd"), "___etc_passwd")
	testing.expect_value(t, sanitize_name(".."), "__")
	testing.expect_value(t, sanitize_name("a\x00b"), "a_b")
	testing.expect_value(t, sanitize_name("会话"), "__")
	testing.expect_value(t, sanitize_name("!!!"), "___")
	testing.expect_value(t, sanitize_name("safe-name_01"), "safe-name_01")
}

@(test)
test_looks_like_session_path :: proc(t: ^testing.T) {
	testing.expect(t, looks_like_session_path("foo/bar"))
	testing.expect(t, looks_like_session_path(`C:\sess.jsonl`))
	testing.expect(t, looks_like_session_path("chat.jsonl"))
	testing.expect(t, !looks_like_session_path("my-session"))
	testing.expect(t, !looks_like_session_path("work_1"))
}

@(test)
test_transcript_roundtrip_with_tools :: proc(t: ^testing.T) {
	path := "/tmp/nullray-store-test.jsonl"
	_ = os.remove(path)
	defer os.remove(path)

	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("yo")})
	append(&msgs, provider.Message{role = .Tool, content = strings.clone("ok"), name = strings.clone("read_file")})
	append(&msgs, provider.Message{role = .System, content = strings.clone("skip")})

	testing.expect(t, save_transcript(path, msgs[:]))

	loaded, ok := load_transcript(path)
	testing.expect(t, ok)
	defer {
		for m in loaded {
			provider.destroy_message(m)
		}
		delete(loaded)
	}
	testing.expect_value(t, len(loaded), 3)
	testing.expect_value(t, loaded[0].role, provider.Role.User)
	testing.expect_value(t, loaded[1].role, provider.Role.Assistant)
	testing.expect_value(t, loaded[2].role, provider.Role.Tool)
	testing.expect_value(t, loaded[2].name, "read_file")
	testing.expect_value(t, loaded[2].content, "ok")
}

@(test)
test_session_export_import_delete :: proc(t: ^testing.T) {
	name := "nullray_lifecycle_test"
	path := named_session_path(name)
	defer {
		_ = os.remove(path)
		_ = os.remove(meta_path_for(path, context.temp_allocator))
		_ = os.remove(session_lock_path(path, context.temp_allocator))
		delete(path)
	}

	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("export-me")})
	testing.expect(t, save_transcript(path, msgs[:]))
	testing.expect(t, save_session_meta(path, Session_Meta{
		provider = "ollama",
		model = "test-model",
		group = "",
		mode = "ask",
	}))

	export_dir := "/tmp/nullray-session-export-test"
	_ = os.remove(fmt.tprintf("%s/%s.jsonl", export_dir, name))
	_ = os.remove(fmt.tprintf("%s/%s.meta.json", export_dir, name))
	ok, err := export_session(name, export_dir)
	testing.expect(t, ok)
	if !ok {
		testing.expectf(t, false, "export failed: %s", err)
	}
	defer {
		_ = os.remove(fmt.tprintf("%s/%s.jsonl", export_dir, name))
		_ = os.remove(fmt.tprintf("%s/%s.meta.json", export_dir, name))
	}

	dok, derr := delete_session(name)
	testing.expect(t, dok)
	if !dok {
		testing.expectf(t, false, "delete failed: %s", derr)
	}
	testing.expect(t, !os.exists(path))

	src_jsonl, jerr := filepath.join({export_dir, fmt.tprintf("%s.jsonl", name)}, context.temp_allocator)
	if jerr != nil {
		src_jsonl = fmt.tprintf("%s/%s.jsonl", export_dir, name)
	}
	imported, iok, ierr := import_session(src_jsonl, name)
	testing.expect(t, iok)
	if !iok {
		testing.expectf(t, false, "import failed: %s", ierr)
	}
	testing.expect_value(t, imported, name)
	testing.expect(t, os.exists(path))

	meta, mok := load_session_meta(path)
	testing.expect(t, mok)
	defer destroy_session_meta(meta)
	testing.expect_value(t, meta.provider, "ollama")
	testing.expect_value(t, meta.model, "test-model")

	dok2, derr2 := delete_session(name)
	testing.expect(t, dok2)
	if !dok2 {
		testing.expectf(t, false, "final delete failed: %s", derr2)
	}
}

@(test)
test_transcript_msgpack_roundtrip :: proc(t: ^testing.T) {
	path := "/tmp/nullray-store-test.msgpack"
	_ = os.remove(path)
	defer os.remove(path)

	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("yo"), reasoning = strings.clone("think")})
	append(&msgs, provider.Message{role = .Tool, content = strings.clone("ok"), name = strings.clone("read_file")})

	testing.expect(t, save_transcript(path, msgs[:]))
	testing.expect(t, session_path_is_msgpack(path))

	loaded, ok := load_transcript(path)
	testing.expect(t, ok)
	defer {
		for m in loaded {
			provider.destroy_message(m)
		}
		delete(loaded)
	}
	testing.expect_value(t, len(loaded), 3)
	testing.expect_value(t, loaded[0].content, "hi")
	testing.expect_value(t, loaded[1].reasoning, "think")
	testing.expect_value(t, loaded[2].name, "read_file")
}

@(test)
test_session_rename_files :: proc(t: ^testing.T) {
	from := "nullray_rename_from"
	to := "nullray_rename_to"
	src := named_session_path(from)
	dst := named_session_path(to)
	defer {
		_, _ = delete_session(from)
		_, _ = delete_session(to)
		delete(src)
		delete(dst)
	}
	_, _ = delete_session(from)
	_, _ = delete_session(to)

	msgs := make([dynamic]provider.Message)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("rename-me")})
	testing.expect(t, save_transcript(src, msgs[:]))
	testing.expect(t, save_session_meta(src, Session_Meta{
		provider = "ollama",
		model = "m",
		group = "",
		mode = "ask",
	}))

	ok, err := rename_session_files(from, to, false)
	testing.expect(t, ok)
	if !ok {
		testing.expectf(t, false, "rename failed: %s", err)
	}
	testing.expect(t, !os.exists(src))
	testing.expect(t, os.exists(dst))
	meta, mok := load_session_meta(dst)
	testing.expect(t, mok)
	defer destroy_session_meta(meta)
	testing.expect_value(t, meta.provider, "ollama")

	ok2, _ := rename_session_files(to, from, false)
	testing.expect(t, ok2)
	testing.expect(t, os.exists(src))

	testing.expect(t, save_transcript(dst, msgs[:]))
	ok3, err3 := rename_session_files(from, to, false)
	testing.expect(t, !ok3)
	testing.expect(t, strings.contains(err3, "already exists"))

	ok4, err4 := rename_session_files(from, to, true)
	testing.expect(t, ok4)
	if !ok4 {
		testing.expectf(t, false, "force rename failed: %s", err4)
	}
	testing.expect(t, !os.exists(src))
	testing.expect(t, os.exists(dst))
}
