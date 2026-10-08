// SPDX-License-Identifier: LicenseRef-QSL-1.0-0BSD
/*
Optional sealed session transcripts.

When NULLRAY_SESSION_KEY is set (or unlocked via /encrypt), msgpack bodies are
wrapped with XChaCha20-Poly1305. Format:

  magic "NRSEAL01" (8)
  salt  (16)
  xiv   (24)
  tag   (16)
  ciphertext (len msgpack)

Without a key, plain .msgpack continues to work. Encrypted files keep the
.msgpack suffix so path helpers stay stable.
*/

package store

import "core:crypto"
import "core:crypto/chacha20poly1305"
import "core:crypto/hash"
import "core:crypto/pbkdf2"
import "core:os"
import "core:strings"
import "nullray:constants"

SEAL_MAGIC :: "NRSEAL01"
SEAL_SALT_SIZE :: 16
SEAL_ITERATIONS :: 120_000

// Process-wide key used by save/load when set. Empty means plain transcripts.
g_session_passphrase: string

session_crypto_set_passphrase :: proc(pass: string) {
	if len(g_session_passphrase) > 0 {
		// best-effort wipe
		raw := transmute([]u8)g_session_passphrase
		for i in 0 ..< len(raw) {
			raw[i] = 0
		}
		delete(g_session_passphrase)
		g_session_passphrase = ""
	}
	if len(pass) > 0 {
		g_session_passphrase = strings.clone(pass)
	}
}

session_crypto_clear_passphrase :: proc() {
	session_crypto_set_passphrase("")
}

session_crypto_has_passphrase :: proc() -> bool {
	return len(g_session_passphrase) > 0
}

session_crypto_passphrase :: proc() -> string {
	if len(g_session_passphrase) > 0 {
		return g_session_passphrase
	}
	if v, ok := os.lookup_env(constants.ENV_SESSION_KEY, context.temp_allocator); ok {
		return strings.trim_space(v)
	}
	return ""
}

session_blob_is_sealed :: proc(data: []u8) -> bool {
	need := 8 + SEAL_SALT_SIZE + chacha20poly1305.XIV_SIZE + chacha20poly1305.TAG_SIZE
	return len(data) >= need && string(data[:8]) == SEAL_MAGIC
}

@(private)
session_derive_key :: proc(passphrase: string, salt: []u8, out_key: []u8) {
	pbkdf2.derive(hash.Algorithm.SHA512_256, transmute([]u8)passphrase, salt, SEAL_ITERATIONS, out_key)
}

session_seal_bytes :: proc(plaintext: []u8, passphrase: string, allocator := context.allocator) -> ([]u8, bool) {
	if len(passphrase) == 0 {
		return nil, false
	}
	salt := make([]u8, SEAL_SALT_SIZE, context.temp_allocator)
	xiv := make([]u8, chacha20poly1305.XIV_SIZE, context.temp_allocator)
	tag := make([]u8, chacha20poly1305.TAG_SIZE, context.temp_allocator)
	key := make([]u8, chacha20poly1305.KEY_SIZE, context.temp_allocator)
	crypto.rand_bytes(salt)
	crypto.rand_bytes(xiv)
	session_derive_key(passphrase, salt, key)

	ct := make([]u8, len(plaintext), context.temp_allocator)
	ctx: chacha20poly1305.Context
	chacha20poly1305.init_xchacha(&ctx, key)
	chacha20poly1305.seal(&ctx, ct, tag, xiv, nil, plaintext)
	chacha20poly1305.reset(&ctx)

	out_len := 8 + SEAL_SALT_SIZE + chacha20poly1305.XIV_SIZE + chacha20poly1305.TAG_SIZE + len(ct)
	out := make([]u8, out_len, allocator)
	copy(out[0:8], transmute([]u8)string(SEAL_MAGIC))
	off := 8
	copy(out[off:off + SEAL_SALT_SIZE], salt)
	off += SEAL_SALT_SIZE
	copy(out[off:off + chacha20poly1305.XIV_SIZE], xiv)
	off += chacha20poly1305.XIV_SIZE
	copy(out[off:off + chacha20poly1305.TAG_SIZE], tag)
	off += chacha20poly1305.TAG_SIZE
	copy(out[off:], ct)
	return out, true
}

session_open_bytes :: proc(blob: []u8, passphrase: string, allocator := context.allocator) -> ([]u8, bool) {
	if !session_blob_is_sealed(blob) || len(passphrase) == 0 {
		return nil, false
	}
	off := 8
	salt := blob[off:off + SEAL_SALT_SIZE]
	off += SEAL_SALT_SIZE
	xiv := blob[off:off + chacha20poly1305.XIV_SIZE]
	off += chacha20poly1305.XIV_SIZE
	tag := blob[off:off + chacha20poly1305.TAG_SIZE]
	off += chacha20poly1305.TAG_SIZE
	ct := blob[off:]

	key := make([]u8, chacha20poly1305.KEY_SIZE, context.temp_allocator)
	session_derive_key(passphrase, salt, key)
	pt := make([]u8, len(ct), allocator)
	ctx: chacha20poly1305.Context
	chacha20poly1305.init_xchacha(&ctx, key)
	ok := chacha20poly1305.open(&ctx, pt, xiv, nil, ct, tag)
	chacha20poly1305.reset(&ctx)
	if !ok {
		delete(pt)
		return nil, false
	}
	return pt, true
}
