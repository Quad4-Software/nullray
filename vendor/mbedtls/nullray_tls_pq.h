/*
 * TLS 1.3 X25519MLKEM768 hybrid helpers for nullray (RFC 10024).
 */

#ifndef NULLRAY_TLS_PQ_H
#define NULLRAY_TLS_PQ_H

#include "mbedtls/mbedtls_config.h"

#if defined(MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_X25519MLKEM768)

#include <stddef.h>
#include <stdint.h>

#include "mbedtls/ssl.h"

#ifdef __cplusplus
extern "C" {
#endif

#define NULLRAY_TLS_X25519MLKEM768_CLIENT_SHARE_LEN 1216
#define NULLRAY_TLS_X25519MLKEM768_SERVER_SHARE_LEN 1120
#define NULLRAY_TLS_X25519MLKEM768_SECRET_LEN      64
#define NULLRAY_TLS_MLKEM768_SK_LEN                 2400
#define NULLRAY_TLS_MLKEM768_PK_LEN                 1184
#define NULLRAY_TLS_MLKEM768_CT_LEN                 1088
#define NULLRAY_TLS_X25519_LEN                      32

int nullray_tls_pq_is_x25519mlkem768(uint16_t group);

/*
 * Generate client KeyShareEntry key_exchange (pk || x25519_pub).
 * Stores ML-KEM sk and X25519 PSA private key on the handshake.
 */
int nullray_tls_pq_write_client_share(mbedtls_ssl_context *ssl,
                                      unsigned char *buf,
                                      unsigned char *end,
                                      size_t *olen);

/*
 * Parse server KeyShareEntry key_exchange (ct || x25519_pub).
 */
int nullray_tls_pq_read_server_share(mbedtls_ssl_context *ssl,
                                     const unsigned char *buf,
                                     size_t buflen);

/*
 * Compute shared secret (mlkem_ss || x25519_ss), 64 bytes.
 * Caller must free *secret with mbedtls_free.
 */
int nullray_tls_pq_compute_shared_secret(mbedtls_ssl_context *ssl,
                                         unsigned char **secret,
                                         size_t *secret_len);

void nullray_tls_pq_reset(mbedtls_ssl_context *ssl);

#ifdef __cplusplus
}
#endif

#endif /* MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_X25519MLKEM768 */

#endif /* NULLRAY_TLS_PQ_H */
