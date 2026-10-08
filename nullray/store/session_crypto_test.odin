// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
package store

import "core:os"
import "core:strings"
import "core:testing"
import "nullray:provider"

@(test)
test_session_seal_open_roundtrip :: proc(t: ^testing.T) {
	plain := transmute([]u8)string("hello sealed session body")
	pass := "test-passphrase-ok"
	sealed, ok := session_seal_bytes(plain, pass, context.allocator)
	testing.expect(t, ok)
	defer delete(sealed)
	testing.expect(t, session_blob_is_sealed(sealed))
	testing.expect(t, !strings.contains(string(sealed), "hello sealed"))

	opened, ook := session_open_bytes(sealed, pass, context.allocator)
	testing.expect(t, ook)
	defer delete(opened)
	testing.expect_value(t, string(opened), "hello sealed session body")

	_, bad := session_open_bytes(sealed, "wrong-pass-xxxxxxxx", context.allocator)
	testing.expect(t, !bad)
}

@(test)
test_transcript_msgpack_sealed_roundtrip :: proc(t: ^testing.T) {
	path := "/tmp/nullray-seal-test.msgpack"
	_ = os.remove(path)
	defer os.remove(path)

	session_crypto_set_passphrase("unit-test-key-1234")
	defer session_crypto_clear_passphrase()

	msgs := make([dynamic]provider.Message, context.allocator)
	defer {
		for m in msgs {
			provider.destroy_message(m)
		}
		delete(msgs)
	}
	append(&msgs, provider.Message{role = .User, content = strings.clone("hi from sealed")})
	append(&msgs, provider.Message{role = .Assistant, content = strings.clone("hello back")})

	testing.expect(t, save_transcript_msgpack(path, msgs[:]))
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, session_blob_is_sealed(data))
	testing.expect(t, !strings.contains(string(data), "hi from sealed"))

	loaded, lok := load_transcript_msgpack(path, context.allocator)
	testing.expect(t, lok)
	defer {
		for m in loaded {
			provider.destroy_message(m)
		}
		delete(loaded)
	}
	testing.expect(t, len(loaded) >= 2)
	testing.expect(t, strings.contains(loaded[0].content, "hi from sealed") || strings.contains(loaded[0].content, "hello"))
}
