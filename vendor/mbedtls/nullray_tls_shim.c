/*
 * Thin TLS client shim for nullray over vendored Mbed TLS.
 */

#include "nullray_tls_shim.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32) || defined(_WIN32_WCE)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
typedef SOCKET nullray_sock_t;
#define NULLRAY_SOCK_INVALID INVALID_SOCKET
#define nullray_sock_send(s, b, l) send(s, (const char *)(b), (int)(l), 0)
#define nullray_sock_recv(s, b, l) recv(s, (char *)(b), (int)(l), 0)
static int nullray_wsa_refs = 0;
#else
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <fcntl.h>
#if defined(__linux__)
#include <sys/random.h>
#endif
typedef int nullray_sock_t;
#define NULLRAY_SOCK_INVALID (-1)
#define nullray_sock_send(s, b, l) send(s, b, l, 0)
#define nullray_sock_recv(s, b, l) recv(s, b, l, 0)
#endif

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/error.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/ssl.h"
#include "mbedtls/ssl_ciphersuites.h"
#include "mbedtls/x509_crt.h"
#if defined(MBEDTLS_PSA_CRYPTO_C)
#include "psa/crypto.h"
#endif

struct Nullray_Tls {
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_context entropy;
    nullray_sock_t sock;
    int handshake_done;
};

static mbedtls_x509_crt g_ca_chain;
static int g_ca_loaded = 0;
static int g_global_init = 0;

static void nullray_tls_set_err(char *err, size_t err_len, const char *msg)
{
    if (err == NULL || err_len == 0) {
        return;
    }
    if (msg == NULL) {
        msg = "unknown TLS error";
    }
    snprintf(err, err_len, "%s", msg);
}

/*
 * Strong OS entropy for hardened hosts where default Mbed TLS poll sources fail.
 */
#if !defined(_WIN32) && !defined(_WIN32_WCE)
static int nullray_os_entropy_poll(void *data, unsigned char *output, size_t len, size_t *olen)
{
    size_t got = 0;

    (void) data;
    if (output == NULL || olen == NULL || len == 0) {
        return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
    }
#if defined(__linux__)
    while (got < len) {
        ssize_t n = getrandom(output + got, len - got, 0);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            break;
        }
        got += (size_t) n;
    }
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || \
    defined(__NetBSD__) || defined(__DragonFly__)
    arc4random_buf(output, len);
    *olen = len;
    return 0;
#endif
    if (got == 0) {
        int fd = open("/dev/urandom", O_RDONLY);
        if (fd >= 0) {
            ssize_t n = read(fd, output, len);
            close(fd);
            if (n > 0) {
                *olen = (size_t) n;
                return 0;
            }
        }
        *olen = 0;
        return MBEDTLS_ERR_ENTROPY_SOURCE_FAILED;
    }
    *olen = got;
    return 0;
}
#endif

static int nullray_tls_map_ssl_io(int ret)
{
    if (ret == MBEDTLS_ERR_SSL_WANT_READ) {
        return NULLRAY_TLS_WANT_READ;
    }
    if (ret == MBEDTLS_ERR_SSL_WANT_WRITE) {
        return NULLRAY_TLS_WANT_WRITE;
    }
#if defined(MBEDTLS_SSL_PROTO_TLS1_3)
    /* Post-handshake NewSessionTicket. Retry the read/write. */
    if (ret == MBEDTLS_ERR_SSL_RECEIVED_NEW_SESSION_TICKET) {
        return NULLRAY_TLS_WANT_READ;
    }
#endif
    if (ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) {
        return 0;
    }
    if (ret < 0) {
        return -1;
    }
    return ret;
}

static int nullray_tls_net_send(void *ctx, const unsigned char *buf, size_t len)
{
    nullray_sock_t fd = *(nullray_sock_t *) ctx;
    int ret;

    if (fd == NULLRAY_SOCK_INVALID) {
        return MBEDTLS_ERR_NET_INVALID_CONTEXT;
    }
    if (len == 0) {
        return 0;
    }

    ret = (int) nullray_sock_send(fd, buf, len);
    if (ret < 0) {
#if defined(_WIN32) || defined(_WIN32_WCE)
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        return MBEDTLS_ERR_NET_SEND_FAILED;
#else
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        if (errno == EINTR) {
            return MBEDTLS_ERR_SSL_WANT_WRITE;
        }
        return MBEDTLS_ERR_NET_SEND_FAILED;
#endif
    }
    return ret;
}

static int nullray_tls_net_recv(void *ctx, unsigned char *buf, size_t len)
{
    nullray_sock_t fd = *(nullray_sock_t *) ctx;
    int ret;

    if (fd == NULLRAY_SOCK_INVALID) {
        return MBEDTLS_ERR_NET_INVALID_CONTEXT;
    }
    if (len == 0) {
        return 0;
    }

    ret = (int) nullray_sock_recv(fd, buf, len);
    if (ret < 0) {
#if defined(_WIN32) || defined(_WIN32_WCE)
        if (WSAGetLastError() == WSAEWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        return MBEDTLS_ERR_NET_RECV_FAILED;
#else
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        if (errno == EINTR) {
            return MBEDTLS_ERR_SSL_WANT_READ;
        }
        return MBEDTLS_ERR_NET_RECV_FAILED;
#endif
    }
    if (ret == 0) {
        return MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY;
    }
    return ret;
}

static int nullray_tls_try_load_file(mbedtls_x509_crt *chain, const char *path)
{
    int ret;

    if (path == NULL || path[0] == '\0') {
        return -1;
    }
    ret = mbedtls_x509_crt_parse_file(chain, path);
    if (ret < 0) {
        return ret;
    }
    return 0;
}

static int nullray_tls_try_load_path(mbedtls_x509_crt *chain, const char *path)
{
    int ret;

    if (path == NULL || path[0] == '\0') {
        return -1;
    }
    ret = mbedtls_x509_crt_parse_path(chain, path);
    if (ret < 0) {
        return ret;
    }
    return 0;
}

static int nullray_tls_load_global_cas(char *err, size_t err_len)
{
    const char *env_file;
    const char *env_dir;
    int ret;

    if (g_ca_loaded) {
        return 0;
    }

    mbedtls_x509_crt_init(&g_ca_chain);

    env_file = getenv("SSL_CERT_FILE");
    env_dir = getenv("SSL_CERT_DIR");

    if (env_file != NULL && env_file[0] != '\0') {
        ret = nullray_tls_try_load_file(&g_ca_chain, env_file);
        if (ret == 0 && g_ca_chain.version != 0) {
            g_ca_loaded = 1;
            return 0;
        }
        mbedtls_x509_crt_free(&g_ca_chain);
        mbedtls_x509_crt_init(&g_ca_chain);
    }

    if (env_dir != NULL && env_dir[0] != '\0') {
        ret = nullray_tls_try_load_path(&g_ca_chain, env_dir);
        if (ret == 0 && g_ca_chain.version != 0) {
            g_ca_loaded = 1;
            return 0;
        }
        mbedtls_x509_crt_free(&g_ca_chain);
        mbedtls_x509_crt_init(&g_ca_chain);
    }

#if defined(__APPLE__)
    if (nullray_tls_try_load_file(&g_ca_chain, "/etc/ssl/cert.pem") == 0 &&
        g_ca_chain.version != 0) {
        g_ca_loaded = 1;
        return 0;
    }
    mbedtls_x509_crt_free(&g_ca_chain);
    mbedtls_x509_crt_init(&g_ca_chain);
#else
    if (nullray_tls_try_load_path(&g_ca_chain, "/etc/ssl/certs") == 0 &&
        g_ca_chain.version != 0) {
        g_ca_loaded = 1;
        return 0;
    }
    mbedtls_x509_crt_free(&g_ca_chain);
    mbedtls_x509_crt_init(&g_ca_chain);

    if (nullray_tls_try_load_file(&g_ca_chain, "/etc/ssl/cert.pem") == 0 &&
        g_ca_chain.version != 0) {
        g_ca_loaded = 1;
        return 0;
    }
    mbedtls_x509_crt_free(&g_ca_chain);
    mbedtls_x509_crt_init(&g_ca_chain);

    if (nullray_tls_try_load_file(&g_ca_chain, "/etc/pki/tls/certs/ca-bundle.crt") == 0 &&
        g_ca_chain.version != 0) {
        g_ca_loaded = 1;
        return 0;
    }
    mbedtls_x509_crt_free(&g_ca_chain);
    mbedtls_x509_crt_init(&g_ca_chain);
#endif

    nullray_tls_set_err(
        err,
        err_len,
        "failed to load CA certificates, set SSL_CERT_FILE or SSL_CERT_DIR");
    return -1;
}

int nullray_tls_global_init(void)
{
#if defined(_WIN32) || defined(_WIN32_WCE)
    WSADATA wsa;

    if (g_global_init == 0) {
        if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
            return -1;
        }
        g_global_init = 1;
    }
#else
    g_global_init = 1;
#endif
#if defined(MBEDTLS_PSA_CRYPTO_C)
    if (psa_crypto_init() != PSA_SUCCESS) {
        return -1;
    }
#endif
    return nullray_tls_load_global_cas(NULL, 0);
}

void nullray_tls_global_cleanup(void)
{
    if (g_ca_loaded) {
        mbedtls_x509_crt_free(&g_ca_chain);
        g_ca_loaded = 0;
    }
#if defined(MBEDTLS_PSA_CRYPTO_C)
    mbedtls_psa_crypto_free();
#endif
#if defined(_WIN32) || defined(_WIN32_WCE)
    if (g_global_init) {
        WSACleanup();
        g_global_init = 0;
    }
#else
    g_global_init = 0;
#endif
}

Nullray_Tls *nullray_tls_new(void)
{
    Nullray_Tls *t = (Nullray_Tls *) calloc(1, sizeof(Nullray_Tls));
    if (t == NULL) {
        return NULL;
    }
    t->sock = NULLRAY_SOCK_INVALID;
    mbedtls_ssl_init(&t->ssl);
    mbedtls_ssl_config_init(&t->conf);
    mbedtls_ctr_drbg_init(&t->ctr_drbg);
    mbedtls_entropy_init(&t->entropy);
#if !defined(_WIN32) && !defined(_WIN32_WCE)
    /* Prefer OS CSPRNG first on hardened kernels (Cachy/hardened hosts). */
    (void) mbedtls_entropy_add_source(
        &t->entropy,
        nullray_os_entropy_poll,
        NULL,
        32,
        MBEDTLS_ENTROPY_SOURCE_STRONG);
#endif
    return t;
}

void nullray_tls_free(Nullray_Tls *t)
{
    if (t == NULL) {
        return;
    }
    nullray_tls_close(t);
    mbedtls_ssl_config_free(&t->conf);
    mbedtls_ctr_drbg_free(&t->ctr_drbg);
    mbedtls_entropy_free(&t->entropy);
    free(t);
}

int nullray_tls_load_cas(Nullray_Tls *t, char *err, size_t err_len)
{
    if (t == NULL) {
        nullray_tls_set_err(err, err_len, "null TLS context");
        return -1;
    }
    return nullray_tls_load_global_cas(err, err_len);
}

int nullray_tls_handshake(Nullray_Tls *t, intptr_t fd, const char *hostname, char *err, size_t err_len)
{
    const char *pers = "nullray_tls";
    int ret;

    if (t == NULL) {
        nullray_tls_set_err(err, err_len, "null TLS context");
        return -1;
    }
#if defined(_WIN32) || defined(_WIN32_WCE)
    if ((nullray_sock_t) fd == NULLRAY_SOCK_INVALID) {
#else
    if (fd < 0) {
#endif
        nullray_tls_set_err(err, err_len, "invalid socket");
        return -1;
    }
    if (hostname == NULL || hostname[0] == '\0') {
        nullray_tls_set_err(err, err_len, "missing TLS hostname");
        return -1;
    }

    ret = nullray_tls_load_global_cas(err, err_len);
    if (ret != 0) {
        return ret;
    }

    t->sock = (nullray_sock_t) fd;

    ret = mbedtls_ctr_drbg_seed(
        &t->ctr_drbg,
        mbedtls_entropy_func,
        &t->entropy,
        (const unsigned char *) pers,
        strlen(pers));
    if (ret != 0) {
        char ebuf[96];
        mbedtls_strerror(ret, ebuf, sizeof(ebuf));
        if (err != NULL && err_len > 0) {
            snprintf(err, err_len, "TLS RNG init failed: %s", ebuf);
        }
        return -1;
    }

    ret = mbedtls_ssl_config_defaults(
        &t->conf,
        MBEDTLS_SSL_IS_CLIENT,
        MBEDTLS_SSL_TRANSPORT_STREAM,
        MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        nullray_tls_set_err(err, err_len, "TLS config init failed");
        return -1;
    }

    mbedtls_ssl_conf_authmode(&t->conf, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&t->conf, &g_ca_chain, NULL);
    mbedtls_ssl_conf_rng(&t->conf, mbedtls_ctr_drbg_random, &t->ctr_drbg);

    {
        /* Prefer PQ hybrid, then classical ECDHE groups. Lifetime: static. */
        static const uint16_t groups[] = {
#if defined(MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_X25519MLKEM768)
            MBEDTLS_SSL_IANA_TLS_GROUP_X25519MLKEM768,
#endif
            MBEDTLS_SSL_IANA_TLS_GROUP_X25519,
            MBEDTLS_SSL_IANA_TLS_GROUP_SECP256R1,
            MBEDTLS_SSL_IANA_TLS_GROUP_SECP384R1,
            MBEDTLS_SSL_IANA_TLS_GROUP_SECP521R1,
            0
        };
        mbedtls_ssl_conf_groups(&t->conf, groups);
    }

    {
        /* TLS 1.3 AEAD + TLS 1.2 ECDHE-AEAD only (no CBC, no static RSA). */
        static const int ciphersuites[] = {
            MBEDTLS_TLS1_3_AES_256_GCM_SHA384,
            MBEDTLS_TLS1_3_CHACHA20_POLY1305_SHA256,
            MBEDTLS_TLS1_3_AES_128_GCM_SHA256,
            MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
            MBEDTLS_TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,
            MBEDTLS_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,
            MBEDTLS_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
            MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
            MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
            0
        };
        mbedtls_ssl_conf_ciphersuites(&t->conf, ciphersuites);
    }

#if defined(MBEDTLS_SSL_ALPN)
    {
        /* Prefer HTTP/2, fall back to HTTP/1.1. Lifetime: static for process. */
        static const char *alpn_protos[] = {"h2", "http/1.1", NULL};
        ret = mbedtls_ssl_conf_alpn_protocols(&t->conf, alpn_protos);
        if (ret != 0) {
            nullray_tls_set_err(err, err_len, "TLS ALPN config failed");
            return -1;
        }
    }
#endif

    ret = mbedtls_ssl_setup(&t->ssl, &t->conf);
    if (ret != 0) {
        nullray_tls_set_err(err, err_len, "TLS setup failed");
        return -1;
    }

    ret = mbedtls_ssl_set_hostname(&t->ssl, hostname);
    if (ret != 0) {
        nullray_tls_set_err(err, err_len, "TLS hostname failed");
        return -1;
    }

    mbedtls_ssl_set_bio(&t->ssl, &t->sock, nullray_tls_net_send, nullray_tls_net_recv, NULL);

    while ((ret = mbedtls_ssl_handshake(&t->ssl)) != 0) {
        if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            char ebuf[128];
            mbedtls_strerror(ret, ebuf, sizeof(ebuf));
            nullray_tls_set_err(err, err_len, ebuf);
            return -1;
        }
    }

    t->handshake_done = 1;
    return 0;
}

const char *nullray_tls_alpn(Nullray_Tls *t)
{
    if (t == NULL || !t->handshake_done) {
        return NULL;
    }
#if defined(MBEDTLS_SSL_ALPN)
    return mbedtls_ssl_get_alpn_protocol(&t->ssl);
#else
    return NULL;
#endif
}

const char *nullray_tls_version(Nullray_Tls *t)
{
    if (t == NULL || !t->handshake_done) {
        return NULL;
    }
    return mbedtls_ssl_get_version(&t->ssl);
}

int nullray_tls_read(Nullray_Tls *t, unsigned char *buf, size_t len)
{
    int ret;

    if (t == NULL || buf == NULL || len == 0) {
        return -1;
    }
    if (!t->handshake_done) {
        return -1;
    }

    ret = mbedtls_ssl_read(&t->ssl, buf, len);
    return nullray_tls_map_ssl_io(ret);
}

int nullray_tls_write(Nullray_Tls *t, const unsigned char *buf, size_t len)
{
    int ret;

    if (t == NULL || buf == NULL || len == 0) {
        return -1;
    }
    if (!t->handshake_done) {
        return -1;
    }

    ret = mbedtls_ssl_write(&t->ssl, buf, len);
    return nullray_tls_map_ssl_io(ret);
}

void nullray_tls_close(Nullray_Tls *t)
{
    if (t == NULL) {
        return;
    }
    if (t->handshake_done) {
        mbedtls_ssl_close_notify(&t->ssl);
    }
    mbedtls_ssl_free(&t->ssl);
    mbedtls_ssl_init(&t->ssl);
    t->sock = NULLRAY_SOCK_INVALID;
    t->handshake_done = 0;
}
