#ifndef NULLRAY_H2_SHIM_H
#define NULLRAY_H2_SHIM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*
 * IO callbacks: return bytes transferred, 0 on clean EOF, negative on error.
 * WANT_READ/WANT_WRITE use the same codes as the TLS shim (-2 / -3).
 */
typedef int (*nullray_h2_io_fn)(void *ctx, unsigned char *buf, size_t len);
typedef int (*nullray_h2_io_const_fn)(void *ctx, const unsigned char *buf, size_t len);
typedef void (*nullray_h2_data_cb)(const unsigned char *data, size_t len, void *user);
/* Return nonzero to abort (cancel or deadline). */
typedef int (*nullray_h2_stop_fn)(void *ctx);

typedef struct Nullray_H2_Header {
    const char *name;
    const char *value;
} Nullray_H2_Header;

/*
 * One buffered HTTP/2 request over an already-negotiated h2 TLS socket.
 * body_out receives up to body_cap bytes. Sets *status_out and *body_len_out.
 * Returns 0 on success (including HTTP error statuses), -1 on transport/protocol error.
 */
int nullray_h2_request(
    nullray_h2_io_fn read_fn,
    nullray_h2_io_const_fn write_fn,
    nullray_h2_stop_fn stop_fn,
    void *io_ctx,
    const char *method,
    const char *path,
    const char *authority,
    const char *scheme,
    const Nullray_H2_Header *headers,
    size_t nheaders,
    const unsigned char *body,
    size_t body_len,
    int *status_out,
    unsigned char *body_out,
    size_t body_cap,
    size_t *body_len_out,
    int *retry_after_out,
    char *location_out,
    size_t location_len,
    char *err,
    size_t err_len);

/*
 * Streaming variant: on_data receives response DATA chunks (may be called many times).
 * For status >= 400, up to err_cap bytes are also copied into err_body.
 */
int nullray_h2_request_stream(
    nullray_h2_io_fn read_fn,
    nullray_h2_io_const_fn write_fn,
    nullray_h2_stop_fn stop_fn,
    void *io_ctx,
    const char *method,
    const char *path,
    const char *authority,
    const char *scheme,
    const Nullray_H2_Header *headers,
    size_t nheaders,
    const unsigned char *body,
    size_t body_len,
    nullray_h2_data_cb on_data,
    void *on_data_user,
    int *status_out,
    unsigned char *err_body,
    size_t err_cap,
    size_t *err_len_out,
    int *retry_after_out,
    char *err,
    size_t err_len);

#ifdef __cplusplus
}
#endif

#endif
