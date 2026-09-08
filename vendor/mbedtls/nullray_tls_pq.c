/*
 * TLS 1.3 X25519MLKEM768 hybrid helpers for nullray (RFC 10024).
 */

#include "mbedtls/mbedtls_config.h"

#if defined(MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_X25519MLKEM768)

#define MBEDTLS_ALLOW_PRIVATE_ACCESS

#include "common.h"

#include "nullray_tls_pq.h"

#include <string.h>

#include "mbedtls/error.h"
#include "mbedtls/platform.h"
#include "mbedtls/platform_util.h"
#include "psa/crypto.h"
#include "psa_util_internal.h"

#include "mlkem_native.h"
#include "ssl_misc.h"

/* Match other TLS 1.3 translation helpers. */
static int local_err_translation(psa_status_t status)
{
    return psa_status_to_mbedtls(status, psa_to_ssl_errors,
                                 ARRAY_LENGTH(psa_to_ssl_errors),
                                 psa_generic_status_to_mbedtls);
}
#define PSA_TO_MBEDTLS_ERR(status) local_err_translation(status)

int nullray_tls_pq_is_x25519mlkem768(uint16_t group)
{
    return group == MBEDTLS_SSL_IANA_TLS_GROUP_X25519MLKEM768;
}

void nullray_tls_pq_reset(mbedtls_ssl_context *ssl)
{
    mbedtls_ssl_handshake_params *hs;

    if (ssl == NULL || ssl->handshake == NULL) {
        return;
    }
    hs = ssl->handshake;
    if (hs->nullray_mlkem_sk_set) {
        mbedtls_platform_zeroize(hs->nullray_mlkem_sk, sizeof(hs->nullray_mlkem_sk));
        hs->nullray_mlkem_sk_set = 0;
    }
    hs->nullray_hybrid_peer_len = 0;
    if (hs->xxdh_psa_privkey != MBEDTLS_SVC_KEY_ID_INIT) {
        (void) psa_destroy_key(hs->xxdh_psa_privkey);
        hs->xxdh_psa_privkey = MBEDTLS_SVC_KEY_ID_INIT;
    }
}

int nullray_tls_pq_write_client_share(mbedtls_ssl_context *ssl,
                                      unsigned char *buf,
                                      unsigned char *end,
                                      size_t *olen)
{
    mbedtls_ssl_handshake_params *hs;
    psa_status_t status;
    psa_key_attributes_t attrs = PSA_KEY_ATTRIBUTES_INIT;
    uint8_t coins[2 * MLKEM_SYMBYTES];
    uint8_t pk[NULLRAY_TLS_MLKEM768_PK_LEN];
    size_t x_len = 0;
    int ret;

    if (ssl == NULL || ssl->handshake == NULL || buf == NULL || olen == NULL) {
        return MBEDTLS_ERR_SSL_BAD_INPUT_DATA;
    }
    hs = ssl->handshake;
    *olen = 0;

    if ((size_t) (end - buf) < NULLRAY_TLS_X25519MLKEM768_CLIENT_SHARE_LEN) {
        return MBEDTLS_ERR_SSL_BUFFER_TOO_SMALL;
    }

    status = psa_generate_random(coins, sizeof(coins));
    if (status != PSA_SUCCESS) {
        return PSA_TO_MBEDTLS_ERR(status);
    }

    ret = mlkem_keypair_derand(pk, hs->nullray_mlkem_sk, coins);
    mbedtls_platform_zeroize(coins, sizeof(coins));
    if (ret != 0) {
        return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    }
    hs->nullray_mlkem_sk_set = 1;

    {
        psa_key_type_t key_type = PSA_KEY_TYPE_NONE;
        size_t bits = 0;

        if (mbedtls_ssl_get_psa_curve_info_from_tls_id(
                MBEDTLS_SSL_IANA_TLS_GROUP_X25519, &key_type, &bits) != PSA_SUCCESS) {
            nullray_tls_pq_reset(ssl);
            return MBEDTLS_ERR_SSL_FEATURE_UNAVAILABLE;
        }

        psa_set_key_usage_flags(&attrs, PSA_KEY_USAGE_DERIVE);
        psa_set_key_algorithm(&attrs, PSA_ALG_ECDH);
        psa_set_key_type(&attrs, key_type);
        psa_set_key_bits(&attrs, bits);

        status = psa_generate_key(&attrs, &hs->xxdh_psa_privkey);
        if (status != PSA_SUCCESS) {
            nullray_tls_pq_reset(ssl);
            return PSA_TO_MBEDTLS_ERR(status);
        }
        hs->xxdh_psa_type = key_type;
        hs->xxdh_psa_bits = bits;
    }

    status = psa_export_public_key(
        hs->xxdh_psa_privkey,
        buf + NULLRAY_TLS_MLKEM768_PK_LEN,
        NULLRAY_TLS_X25519_LEN,
        &x_len);
    if (status != PSA_SUCCESS || x_len != NULLRAY_TLS_X25519_LEN) {
        nullray_tls_pq_reset(ssl);
        return status != PSA_SUCCESS ? PSA_TO_MBEDTLS_ERR(status)
                                     : MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    }

    memcpy(buf, pk, NULLRAY_TLS_MLKEM768_PK_LEN);
    *olen = NULLRAY_TLS_X25519MLKEM768_CLIENT_SHARE_LEN;
    return 0;
}

int nullray_tls_pq_read_server_share(mbedtls_ssl_context *ssl,
                                     const unsigned char *buf,
                                     size_t buflen)
{
    mbedtls_ssl_handshake_params *hs;
    const unsigned char *p = buf;
    size_t key_exchange_len;

    if (ssl == NULL || ssl->handshake == NULL || buf == NULL) {
        return MBEDTLS_ERR_SSL_BAD_INPUT_DATA;
    }
    hs = ssl->handshake;

    if (buflen < 2) {
        return MBEDTLS_ERR_SSL_DECODE_ERROR;
    }
    key_exchange_len = ((size_t) p[0] << 8) | p[1];
    p += 2;
    if (key_exchange_len != NULLRAY_TLS_X25519MLKEM768_SERVER_SHARE_LEN ||
        buflen < 2 + key_exchange_len) {
        return MBEDTLS_ERR_SSL_DECODE_ERROR;
    }

    memcpy(hs->nullray_hybrid_peer, p, key_exchange_len);
    hs->nullray_hybrid_peer_len = key_exchange_len;
    return 0;
}

int nullray_tls_pq_compute_shared_secret(mbedtls_ssl_context *ssl,
                                         unsigned char **secret,
                                         size_t *secret_len)
{
    mbedtls_ssl_handshake_params *hs;
    unsigned char *out = NULL;
    uint8_t mlkem_ss[MLKEM_BYTES];
    size_t x_len = 0;
    psa_status_t status;
    int ret;

    if (ssl == NULL || ssl->handshake == NULL || secret == NULL || secret_len == NULL) {
        return MBEDTLS_ERR_SSL_BAD_INPUT_DATA;
    }
    hs = ssl->handshake;
    *secret = NULL;
    *secret_len = 0;

    if (!hs->nullray_mlkem_sk_set ||
        hs->nullray_hybrid_peer_len != NULLRAY_TLS_X25519MLKEM768_SERVER_SHARE_LEN) {
        return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    }

    ret = mlkem_dec(
        mlkem_ss,
        hs->nullray_hybrid_peer,
        hs->nullray_mlkem_sk);
    if (ret != 0) {
        return MBEDTLS_ERR_SSL_HANDSHAKE_FAILURE;
    }

    out = mbedtls_calloc(1, NULLRAY_TLS_X25519MLKEM768_SECRET_LEN);
    if (out == NULL) {
        mbedtls_platform_zeroize(mlkem_ss, sizeof(mlkem_ss));
        return MBEDTLS_ERR_SSL_ALLOC_FAILED;
    }

    status = psa_raw_key_agreement(
        PSA_ALG_ECDH,
        hs->xxdh_psa_privkey,
        hs->nullray_hybrid_peer + NULLRAY_TLS_MLKEM768_CT_LEN,
        NULLRAY_TLS_X25519_LEN,
        out + MLKEM_BYTES,
        NULLRAY_TLS_X25519_LEN,
        &x_len);
    if (status != PSA_SUCCESS || x_len != NULLRAY_TLS_X25519_LEN) {
        mbedtls_platform_zeroize(mlkem_ss, sizeof(mlkem_ss));
        mbedtls_platform_zeroize(out, NULLRAY_TLS_X25519MLKEM768_SECRET_LEN);
        mbedtls_free(out);
        return status != PSA_SUCCESS ? PSA_TO_MBEDTLS_ERR(status)
                                     : MBEDTLS_ERR_SSL_INTERNAL_ERROR;
    }

    memcpy(out, mlkem_ss, MLKEM_BYTES);
    mbedtls_platform_zeroize(mlkem_ss, sizeof(mlkem_ss));

    (void) psa_destroy_key(hs->xxdh_psa_privkey);
    hs->xxdh_psa_privkey = MBEDTLS_SVC_KEY_ID_INIT;
    mbedtls_platform_zeroize(hs->nullray_mlkem_sk, sizeof(hs->nullray_mlkem_sk));
    hs->nullray_mlkem_sk_set = 0;
    hs->nullray_hybrid_peer_len = 0;

    *secret = out;
    *secret_len = NULLRAY_TLS_X25519MLKEM768_SECRET_LEN;
    return 0;
}

#endif /* MBEDTLS_SSL_TLS1_3_KEY_EXCHANGE_MODE_EPHEMERAL_X25519MLKEM768 */
