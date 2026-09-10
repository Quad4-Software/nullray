/*
 * Minimal HTTP/2 client for one request over an existing TLS socket.
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include "nullray_h2_shim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nghttp2/nghttp2.h>

#define NULLRAY_H2_WANT_READ  (-2)
#define NULLRAY_H2_WANT_WRITE (-3)

typedef struct {
    nullray_h2_io_fn read_fn;
    nullray_h2_io_const_fn write_fn;
    nullray_h2_stop_fn stop_fn;
    void *io_ctx;
    nullray_h2_data_cb on_data;
    void *on_data_user;
    unsigned char *body_out;
    size_t body_cap;
    size_t body_len;
    unsigned char *err_body;
    size_t err_cap;
    size_t err_len;
    int status;
    int retry_after;
    char location[1024];
    int stream_id;
    int stream_closed;
    int session_done;
    int fatal;
    char err[160];
} Nullray_H2_Ctx;

static void nullray_h2_set_err(Nullray_H2_Ctx *c, const char *msg)
{
    if (c == NULL) {
        return;
    }
    /* Keep the first error (e.g. response body too large over frame parse). */
    if (c->err[0] != '\0') {
        return;
    }
    if (msg == NULL) {
        msg = "HTTP/2 error";
    }
    snprintf(c->err, sizeof(c->err), "%s", msg);
    c->fatal = 1;
}

static ssize_t nullray_h2_send_cb(
    nghttp2_session *session,
    const uint8_t *data,
    size_t length,
    int flags,
    void *user_data)
{
    Nullray_H2_Ctx *c = (Nullray_H2_Ctx *) user_data;
    int n;

    (void) session;
    (void) flags;
    n = c->write_fn(c->io_ctx, data, length);
    if (n == NULLRAY_H2_WANT_WRITE || n == NULLRAY_H2_WANT_READ) {
        return NGHTTP2_ERR_WOULDBLOCK;
    }
    if (n < 0) {
        return NGHTTP2_ERR_CALLBACK_FAILURE;
    }
    if (n == 0) {
        return NGHTTP2_ERR_CALLBACK_FAILURE;
    }
    return n;
}

static int nullray_h2_on_frame_recv(nghttp2_session *session, const nghttp2_frame *frame, void *user_data)
{
    Nullray_H2_Ctx *c = (Nullray_H2_Ctx *) user_data;

    (void) session;
    if (frame->hd.type == NGHTTP2_GOAWAY) {
        c->session_done = 1;
    }
    return 0;
}

static int nullray_h2_on_header(
    nghttp2_session *session,
    const nghttp2_frame *frame,
    const uint8_t *name,
    size_t namelen,
    const uint8_t *value,
    size_t valuelen,
    uint8_t flags,
    void *user_data)
{
    Nullray_H2_Ctx *c = (Nullray_H2_Ctx *) user_data;

    (void) session;
    (void) flags;
    if (frame->hd.type != NGHTTP2_HEADERS || frame->headers.cat != NGHTTP2_HCAT_RESPONSE) {
        return 0;
    }
    if (namelen == 7 && memcmp(name, ":status", 7) == 0) {
        char buf[16];
        size_t n = valuelen < sizeof(buf) - 1 ? valuelen : sizeof(buf) - 1;
        memcpy(buf, value, n);
        buf[n] = '\0';
        c->status = atoi(buf);
    } else if (namelen == 11 && memcmp(name, "retry-after", 11) == 0) {
        char buf[32];
        size_t n = valuelen < sizeof(buf) - 1 ? valuelen : sizeof(buf) - 1;
        int v;
        memcpy(buf, value, n);
        buf[n] = '\0';
        v = atoi(buf);
        if (v > 0) {
            c->retry_after = v;
        }
    } else if (namelen == 8 && memcmp(name, "location", 8) == 0) {
        size_t n = valuelen < sizeof(c->location) - 1 ? valuelen : sizeof(c->location) - 1;
        memcpy(c->location, value, n);
        c->location[n] = '\0';
    }
    return 0;
}

static int nullray_h2_on_data(
    nghttp2_session *session,
    uint8_t flags,
    int32_t stream_id,
    const uint8_t *data,
    size_t len,
    void *user_data)
{
    Nullray_H2_Ctx *c = (Nullray_H2_Ctx *) user_data;

    (void) session;
    (void) flags;
    if (stream_id != c->stream_id) {
        return 0;
    }
    if (c->on_data != NULL) {
        c->on_data(data, len, c->on_data_user);
    }
    if (c->body_out != NULL && len > 0) {
        if (c->body_len >= c->body_cap) {
            nullray_h2_set_err(c, "response body too large");
            return NGHTTP2_ERR_CALLBACK_FAILURE;
        }
        {
            size_t n = len;
            if (c->body_len + n > c->body_cap) {
                n = c->body_cap - c->body_len;
            }
            memcpy(c->body_out + c->body_len, data, n);
            c->body_len += n;
            if (len > n) {
                nullray_h2_set_err(c, "response body too large");
                return NGHTTP2_ERR_CALLBACK_FAILURE;
            }
        }
    }
    if (c->err_body != NULL && c->err_len < c->err_cap) {
        size_t n = len;
        if (c->err_len + n > c->err_cap) {
            n = c->err_cap - c->err_len;
        }
        memcpy(c->err_body + c->err_len, data, n);
        c->err_len += n;
    }
    return 0;
}

static int nullray_h2_on_stream_close(
    nghttp2_session *session,
    int32_t stream_id,
    uint32_t error_code,
    void *user_data)
{
    Nullray_H2_Ctx *c = (Nullray_H2_Ctx *) user_data;

    (void) session;
    if (stream_id == c->stream_id) {
        c->stream_closed = 1;
        if (error_code != 0 && c->status == 0) {
            nullray_h2_set_err(c, "HTTP/2 stream reset");
        }
    }
    return 0;
}

typedef struct {
    const unsigned char *data;
    size_t len;
    size_t off;
} Nullray_H2_Body;

static ssize_t nullray_h2_body_read(
    nghttp2_session *session,
    int32_t stream_id,
    uint8_t *buf,
    size_t length,
    uint32_t *data_flags,
    nghttp2_data_source *source,
    void *user_data)
{
    Nullray_H2_Body *b = (Nullray_H2_Body *) source->ptr;
    size_t n;

    (void) session;
    (void) stream_id;
    (void) user_data;
    if (b->off >= b->len) {
        *data_flags |= NGHTTP2_DATA_FLAG_EOF;
        return 0;
    }
    n = b->len - b->off;
    if (n > length) {
        n = length;
    }
    memcpy(buf, b->data + b->off, n);
    b->off += n;
    if (b->off >= b->len) {
        *data_flags |= NGHTTP2_DATA_FLAG_EOF;
    }
    return (ssize_t) n;
}

static int nullray_h2_pump(nghttp2_session *session, Nullray_H2_Ctx *c)
{
    unsigned char rbuf[16384];
    int rv;

    for (;;) {
        if (c->fatal) {
            return -1;
        }
        if (c->stop_fn != NULL && c->stop_fn(c->io_ctx) != 0) {
            nullray_h2_set_err(c, "cancelled");
            return -1;
        }
        while (nghttp2_session_want_write(session)) {
            rv = nghttp2_session_send(session);
            if (rv == NGHTTP2_ERR_WOULDBLOCK) {
                break;
            }
            if (rv != 0) {
                nullray_h2_set_err(c, "HTTP/2 send failed");
                return -1;
            }
        }
        if (c->stream_closed && !nghttp2_session_want_write(session)) {
            return 0;
        }
        if (!nghttp2_session_want_read(session) && c->stream_closed) {
            return 0;
        }
        {
            int n = c->read_fn(c->io_ctx, rbuf, sizeof(rbuf));
            if (n == NULLRAY_H2_WANT_READ || n == NULLRAY_H2_WANT_WRITE) {
                continue;
            }
            if (n < 0) {
                nullray_h2_set_err(c, "HTTP/2 read failed");
                return -1;
            }
            if (n == 0) {
                if (c->stream_closed) {
                    return 0;
                }
                nullray_h2_set_err(c, "connection closed");
                return -1;
            }
            rv = (int) nghttp2_session_mem_recv(session, rbuf, (size_t) n);
            if (rv < 0) {
                nullray_h2_set_err(c, "HTTP/2 frame parse failed");
                return -1;
            }
        }
        if (c->session_done && c->stream_closed) {
            return 0;
        }
    }
}

static int nullray_h2_run(
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
    unsigned char *body_out,
    size_t body_cap,
    size_t *body_len_out,
    unsigned char *err_body,
    size_t err_cap,
    size_t *err_len_out,
    int *retry_after_out,
    char *location_out,
    size_t location_len,
    char *err,
    size_t err_len)
{
    Nullray_H2_Ctx ctx;
    nghttp2_session *session = NULL;
    nghttp2_session_callbacks *callbacks = NULL;
    nghttp2_nv *nva = NULL;
    size_t nvlen = 0;
    size_t i;
    int rv;
    int32_t stream_id;
    Nullray_H2_Body body_src;
    nghttp2_data_provider data_prd;
    int has_body = body != NULL && body_len > 0;
    int ok = -1;

    memset(&ctx, 0, sizeof(ctx));
    ctx.read_fn = read_fn;
    ctx.write_fn = write_fn;
    ctx.stop_fn = stop_fn;
    ctx.io_ctx = io_ctx;
    ctx.on_data = on_data;
    ctx.on_data_user = on_data_user;
    ctx.body_out = body_out;
    ctx.body_cap = body_cap;
    ctx.err_body = err_body;
    ctx.err_cap = err_cap;

    if (method == NULL || path == NULL || authority == NULL || scheme == NULL) {
        nullray_h2_set_err(&ctx, "missing HTTP/2 request fields");
        goto done;
    }
    if (read_fn == NULL || write_fn == NULL) {
        nullray_h2_set_err(&ctx, "missing HTTP/2 IO");
        goto done;
    }

    rv = nghttp2_session_callbacks_new(&callbacks);
    if (rv != 0) {
        nullray_h2_set_err(&ctx, "HTTP/2 callbacks alloc failed");
        goto done;
    }
    nghttp2_session_callbacks_set_send_callback(callbacks, nullray_h2_send_cb);
    nghttp2_session_callbacks_set_on_frame_recv_callback(callbacks, nullray_h2_on_frame_recv);
    nghttp2_session_callbacks_set_on_header_callback(callbacks, nullray_h2_on_header);
    nghttp2_session_callbacks_set_on_data_chunk_recv_callback(callbacks, nullray_h2_on_data);
    nghttp2_session_callbacks_set_on_stream_close_callback(callbacks, nullray_h2_on_stream_close);

    rv = nghttp2_session_client_new(&session, callbacks, &ctx);
    nghttp2_session_callbacks_del(callbacks);
    callbacks = NULL;
    if (rv != 0) {
        nullray_h2_set_err(&ctx, "HTTP/2 session init failed");
        goto done;
    }

    {
        nghttp2_settings_entry iv[1];
        iv[0].settings_id = NGHTTP2_SETTINGS_MAX_CONCURRENT_STREAMS;
        iv[0].value = 100;
        rv = nghttp2_submit_settings(session, NGHTTP2_FLAG_NONE, iv, 1);
        if (rv != 0) {
            nullray_h2_set_err(&ctx, "HTTP/2 SETTINGS failed");
            goto done;
        }
    }

    nvlen = 4 + nheaders;
    nva = (nghttp2_nv *) calloc(nvlen, sizeof(nghttp2_nv));
    if (nva == NULL) {
        nullray_h2_set_err(&ctx, "out of memory");
        goto done;
    }
    nva[0].name = (uint8_t *) ":method";
    nva[0].namelen = 7;
    nva[0].value = (uint8_t *) method;
    nva[0].valuelen = strlen(method);
    nva[0].flags = NGHTTP2_NV_FLAG_NONE;

    nva[1].name = (uint8_t *) ":path";
    nva[1].namelen = 5;
    nva[1].value = (uint8_t *) path;
    nva[1].valuelen = strlen(path);
    nva[1].flags = NGHTTP2_NV_FLAG_NONE;

    nva[2].name = (uint8_t *) ":scheme";
    nva[2].namelen = 7;
    nva[2].value = (uint8_t *) scheme;
    nva[2].valuelen = strlen(scheme);
    nva[2].flags = NGHTTP2_NV_FLAG_NONE;

    nva[3].name = (uint8_t *) ":authority";
    nva[3].namelen = 10;
    nva[3].value = (uint8_t *) authority;
    nva[3].valuelen = strlen(authority);
    nva[3].flags = NGHTTP2_NV_FLAG_NONE;

    for (i = 0; i < nheaders; i++) {
        if (headers[i].name == NULL || headers[i].value == NULL) {
            continue;
        }
        nva[4 + i].name = (uint8_t *) headers[i].name;
        nva[4 + i].namelen = strlen(headers[i].name);
        nva[4 + i].value = (uint8_t *) headers[i].value;
        nva[4 + i].valuelen = strlen(headers[i].value);
        nva[4 + i].flags = NGHTTP2_NV_FLAG_NONE;
    }

    memset(&data_prd, 0, sizeof(data_prd));
    body_src.data = body;
    body_src.len = body_len;
    body_src.off = 0;
    if (has_body) {
        data_prd.source.ptr = &body_src;
        data_prd.read_callback = nullray_h2_body_read;
        stream_id = nghttp2_submit_request(session, NULL, nva, nvlen, &data_prd, NULL);
    } else {
        stream_id = nghttp2_submit_request(session, NULL, nva, nvlen, NULL, NULL);
    }
    if (stream_id < 0) {
        nullray_h2_set_err(&ctx, "HTTP/2 submit failed");
        goto done;
    }
    ctx.stream_id = stream_id;

    if (nullray_h2_pump(session, &ctx) != 0) {
        goto done;
    }
    if (ctx.status == 0) {
        nullray_h2_set_err(&ctx, "HTTP/2 missing status");
        goto done;
    }
    ok = 0;

done:
    if (status_out != NULL) {
        *status_out = ctx.status;
    }
    if (body_len_out != NULL) {
        *body_len_out = ctx.body_len;
    }
    if (err_len_out != NULL) {
        *err_len_out = ctx.err_len;
    }
    if (retry_after_out != NULL) {
        *retry_after_out = ctx.retry_after;
    }
    if (location_out != NULL && location_len > 0) {
        snprintf(location_out, location_len, "%s", ctx.location);
    }
    if (ok != 0 && err != NULL && err_len > 0) {
        snprintf(err, err_len, "%s", ctx.err[0] != '\0' ? ctx.err : "HTTP/2 error");
    }
    free(nva);
    if (session != NULL) {
        nghttp2_session_del(session);
    }
    return ok;
}

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
    size_t err_len)
{
    return nullray_h2_run(
        read_fn,
        write_fn,
        stop_fn,
        io_ctx,
        method,
        path,
        authority,
        scheme,
        headers,
        nheaders,
        body,
        body_len,
        NULL,
        NULL,
        status_out,
        body_out,
        body_cap,
        body_len_out,
        NULL,
        0,
        NULL,
        retry_after_out,
        location_out,
        location_len,
        err,
        err_len);
}

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
    size_t err_len)
{
    return nullray_h2_run(
        read_fn,
        write_fn,
        stop_fn,
        io_ctx,
        method,
        path,
        authority,
        scheme,
        headers,
        nheaders,
        body,
        body_len,
        on_data,
        on_data_user,
        status_out,
        NULL,
        0,
        NULL,
        err_body,
        err_cap,
        err_len_out,
        retry_after_out,
        NULL,
        0,
        err,
        err_len);
}
