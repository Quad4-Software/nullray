# Mbed TLS (vendored)

Pinned release: see VERSION.

Tree keeps include/ and library/ only. Built as lib/libnullray_tls.a with the
trimmed client config in include/mbedtls/mbedtls_config.h (TLS 1.2 and 1.3
client with middlebox compatibility, ALPN for h2 and http/1.1, PSA crypto,
X25519MLKEM768 hybrid via vendor/mlkem-native, no DTLS, no server). nghttp2
objects land in the same archive.

Upstream: https://github.com/Mbed-TLS/mbedtls
License: Apache-2.0 OR GPL-2.0-or-later (see LICENSE).
