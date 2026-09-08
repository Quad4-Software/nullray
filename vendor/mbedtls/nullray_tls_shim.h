#ifndef NULLRAY_TLS_SHIM_H
#define NULLRAY_TLS_SHIM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define NULLRAY_TLS_WANT_READ  (-2)
#define NULLRAY_TLS_WANT_WRITE (-3)

int nullray_tls_global_init(void);
void nullray_tls_global_cleanup(void);

typedef struct Nullray_Tls Nullray_Tls;

Nullray_Tls *nullray_tls_new(void);
void nullray_tls_free(Nullray_Tls *t);

int nullray_tls_load_cas(Nullray_Tls *t, char *err, size_t err_len);
int nullray_tls_handshake(Nullray_Tls *t, intptr_t fd, const char *hostname, char *err, size_t err_len);
/*
 * After a successful handshake, returns the ALPN protocol name ("h2" or
 * "http/1.1") or NULL when the peer did not negotiate ALPN.
 */
const char *nullray_tls_alpn(Nullray_Tls *t);
/* Negotiated TLS version string after handshake, e.g. "TLSv1.3". */
const char *nullray_tls_version(Nullray_Tls *t);
int nullray_tls_read(Nullray_Tls *t, unsigned char *buf, size_t len);
int nullray_tls_write(Nullray_Tls *t, const unsigned char *buf, size_t len);
void nullray_tls_close(Nullray_Tls *t);

#ifdef __cplusplus
}
#endif

#endif
