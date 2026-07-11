#include "blufi_example.h"

#include <stdlib.h>
#include <string.h>

#include "esp_blufi.h"
#include "esp_crc.h"
#include "esp_log.h"
#include "esp_random.h"
#include "mbedtls/aes.h"
#include "mbedtls/dhm.h"
#include "mbedtls/md5.h"

extern void btc_blufi_report_error(esp_blufi_error_state_t state);

#define SEC_TYPE_DH_PARAM_LEN 0x00
#define SEC_TYPE_DH_PARAM_DATA 0x01

struct blufi_security {
#define DH_SELF_PUB_KEY_LEN 128
    uint8_t self_public_key[DH_SELF_PUB_KEY_LEN];
#define SHARE_KEY_LEN 128
    uint8_t share_key[SHARE_KEY_LEN];
    size_t share_len;
#define PSK_LEN 16
    uint8_t psk[PSK_LEN];
    uint8_t *dh_param;
    int dh_param_len;
    uint8_t iv[16];
    mbedtls_dhm_context dhm;
    mbedtls_aes_context aes;
};

static struct blufi_security *s_blufi_sec;

static int myrand(void *rng_state, unsigned char *output, size_t len)
{
    (void)rng_state;
    esp_fill_random(output, len);
    return 0;
}

void blufi_dh_negotiate_data_handler(
    uint8_t *data,
    int len,
    uint8_t **output_data,
    int *output_len,
    bool *need_free)
{
    if (!data || len < 3 || !s_blufi_sec) {
        btc_blufi_report_error(ESP_BLUFI_DATA_FORMAT_ERROR);
        return;
    }

    int ret = 0;
    uint8_t type = data[0];
    switch (type) {
        case SEC_TYPE_DH_PARAM_LEN:
            s_blufi_sec->dh_param_len = (data[1] << 8) | data[2];
            free(s_blufi_sec->dh_param);
            s_blufi_sec->dh_param = malloc(s_blufi_sec->dh_param_len);
            if (!s_blufi_sec->dh_param) {
                btc_blufi_report_error(ESP_BLUFI_DH_MALLOC_ERROR);
            }
            break;
        case SEC_TYPE_DH_PARAM_DATA: {
            if (!s_blufi_sec->dh_param || len < (s_blufi_sec->dh_param_len + 1)) {
                btc_blufi_report_error(ESP_BLUFI_DH_PARAM_ERROR);
                return;
            }

            uint8_t *param = s_blufi_sec->dh_param;
            memcpy(s_blufi_sec->dh_param, &data[1], s_blufi_sec->dh_param_len);
            ret = mbedtls_dhm_read_params(
                &s_blufi_sec->dhm,
                &param,
                &param[s_blufi_sec->dh_param_len]);
            if (ret) {
                btc_blufi_report_error(ESP_BLUFI_READ_PARAM_ERROR);
                return;
            }

            const int dhm_len = mbedtls_dhm_get_len(&s_blufi_sec->dhm);
            ret = mbedtls_dhm_make_public(
                &s_blufi_sec->dhm,
                dhm_len,
                s_blufi_sec->self_public_key,
                DH_SELF_PUB_KEY_LEN,
                myrand,
                NULL);
            if (ret) {
                btc_blufi_report_error(ESP_BLUFI_MAKE_PUBLIC_ERROR);
                return;
            }

            ret = mbedtls_dhm_calc_secret(
                &s_blufi_sec->dhm,
                s_blufi_sec->share_key,
                SHARE_KEY_LEN,
                &s_blufi_sec->share_len,
                myrand,
                NULL);
            if (ret) {
                btc_blufi_report_error(ESP_BLUFI_DH_PARAM_ERROR);
                return;
            }

            ret = mbedtls_md5(
                s_blufi_sec->share_key,
                s_blufi_sec->share_len,
                s_blufi_sec->psk);
            if (ret) {
                btc_blufi_report_error(ESP_BLUFI_CALC_MD5_ERROR);
                return;
            }

            mbedtls_aes_setkey_enc(&s_blufi_sec->aes, s_blufi_sec->psk, PSK_LEN * 8);
            *output_data = s_blufi_sec->self_public_key;
            *output_len = dhm_len;
            *need_free = false;

            free(s_blufi_sec->dh_param);
            s_blufi_sec->dh_param = NULL;
            s_blufi_sec->dh_param_len = 0;
            break;
        }
        default:
            break;
    }
}

int blufi_aes_encrypt(uint8_t iv8, uint8_t *crypt_data, int crypt_len)
{
    if (!s_blufi_sec) {
        return -1;
    }

    size_t iv_offset = 0;
    uint8_t iv0[16];
    memcpy(iv0, s_blufi_sec->iv, sizeof(s_blufi_sec->iv));
    iv0[0] = iv8;
    int ret = mbedtls_aes_crypt_cfb128(
        &s_blufi_sec->aes,
        MBEDTLS_AES_ENCRYPT,
        crypt_len,
        &iv_offset,
        iv0,
        crypt_data,
        crypt_data);
    return ret == 0 ? crypt_len : -1;
}

int blufi_aes_decrypt(uint8_t iv8, uint8_t *crypt_data, int crypt_len)
{
    if (!s_blufi_sec) {
        return -1;
    }

    size_t iv_offset = 0;
    uint8_t iv0[16];
    memcpy(iv0, s_blufi_sec->iv, sizeof(s_blufi_sec->iv));
    iv0[0] = iv8;
    int ret = mbedtls_aes_crypt_cfb128(
        &s_blufi_sec->aes,
        MBEDTLS_AES_DECRYPT,
        crypt_len,
        &iv_offset,
        iv0,
        crypt_data,
        crypt_data);
    return ret == 0 ? crypt_len : -1;
}

uint16_t blufi_crc_checksum(uint8_t iv8, uint8_t *data, int len)
{
    (void)iv8;
    return esp_crc16_be(0, data, len);
}

int blufi_security_init(void)
{
    s_blufi_sec = malloc(sizeof(struct blufi_security));
    if (!s_blufi_sec) {
        return ESP_FAIL;
    }

    memset(s_blufi_sec, 0, sizeof(struct blufi_security));
    mbedtls_dhm_init(&s_blufi_sec->dhm);
    mbedtls_aes_init(&s_blufi_sec->aes);
    memset(s_blufi_sec->iv, 0, sizeof(s_blufi_sec->iv));
    return ESP_OK;
}

void blufi_security_deinit(void)
{
    if (!s_blufi_sec) {
        return;
    }

    free(s_blufi_sec->dh_param);
    s_blufi_sec->dh_param = NULL;
    mbedtls_dhm_free(&s_blufi_sec->dhm);
    mbedtls_aes_free(&s_blufi_sec->aes);
    memset(s_blufi_sec, 0, sizeof(struct blufi_security));
    free(s_blufi_sec);
    s_blufi_sec = NULL;
}
