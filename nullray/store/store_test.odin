package store

import "core:os"
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
