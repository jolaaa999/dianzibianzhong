#include "blufi_example.h"

#include "esp_blufi.h"
#include "esp_log.h"

#if CONFIG_BT_CONTROLLER_ENABLED || !CONFIG_BT_NIMBLE_ENABLED
#include "esp_bt.h"
#endif

#ifdef CONFIG_BT_BLUEDROID_ENABLED
#include "esp_bt_device.h"
#include "esp_bt_main.h"
#include "esp_gap_ble_api.h"
#endif

#ifdef CONFIG_BT_NIMBLE_ENABLED
#include "console/console.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

extern void esp_blufi_gatt_svr_register_cb(struct ble_gatt_register_ctxt *ctxt, void *arg);
extern int esp_blufi_gatt_svr_init(void);
extern int esp_blufi_gatt_svr_deinit(void);
extern void esp_blufi_btc_init(void);
extern void esp_blufi_btc_deinit(void);
#endif

extern void esp_blufi_adv_start(void);

#ifdef CONFIG_BT_BLUEDROID_ENABLED
void esp_blufi_gap_event_handler(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param);
#endif

#ifdef CONFIG_BT_BLUEDROID_ENABLED
static const char *kDeviceName = "BianzongHammer";

static esp_err_t esp_blufi_host_init(void)
{
    int ret = esp_bluedroid_init();
    if (ret) {
        return ESP_FAIL;
    }

    ret = esp_bluedroid_enable();
    if (ret) {
        return ESP_FAIL;
    }

    ret = esp_ble_gap_set_device_name(kDeviceName);
    if (ret) {
        return ESP_FAIL;
    }

    return ESP_OK;
}

esp_err_t esp_blufi_host_deinit(void)
{
    int ret = esp_blufi_profile_deinit();
    if (ret != ESP_OK) {
        return ret;
    }

    ret = esp_bluedroid_disable();
    if (ret) {
        return ESP_FAIL;
    }

    ret = esp_bluedroid_deinit();
    if (ret) {
        return ESP_FAIL;
    }

    return ESP_OK;
}

static esp_err_t esp_blufi_gap_register_callback(void)
{
    int rc = esp_ble_gap_register_callback(esp_blufi_gap_event_handler);
    if (rc) {
        return rc;
    }
    return esp_blufi_profile_init();
}

esp_err_t esp_blufi_host_and_cb_init(esp_blufi_callbacks_t *callbacks)
{
    esp_err_t ret = esp_blufi_host_init();
    if (ret) {
        return ret;
    }

    ret = esp_blufi_register_callbacks(callbacks);
    if (ret) {
        return ret;
    }

    return esp_blufi_gap_register_callback();
}
#endif

#ifdef CONFIG_BT_NIMBLE_ENABLED
void ble_store_config_init(void);

static void blufi_on_reset(int reason)
{
    ESP_LOGE(BLUFI_EXAMPLE_TAG, "NimBLE reset reason=%d", reason);
}

static void blufi_on_sync(void)
{
    esp_blufi_profile_init();
}

static void blufi_host_task(void *param)
{
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static esp_err_t esp_blufi_host_init(void)
{
    esp_err_t err = esp_nimble_init();
    if (err) {
        return ESP_FAIL;
    }

    ble_hs_cfg.reset_cb = blufi_on_reset;
    ble_hs_cfg.sync_cb = blufi_on_sync;
    ble_hs_cfg.gatts_register_cb = esp_blufi_gatt_svr_register_cb;
    ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
    ble_hs_cfg.sm_io_cap = 4;

    int rc = esp_blufi_gatt_svr_init();
    if (rc != 0) {
        return ESP_FAIL;
    }

#if CONFIG_BT_NIMBLE_GAP_SERVICE
    rc = ble_svc_gap_device_name_set("BianzongHammer");
    if (rc != 0) {
        return ESP_FAIL;
    }
#endif

    ble_store_config_init();
    esp_blufi_btc_init();

    err = esp_nimble_enable(blufi_host_task);
    if (err) {
        return ESP_FAIL;
    }
    return ESP_OK;
}

esp_err_t esp_blufi_host_deinit(void)
{
    esp_blufi_gatt_svr_deinit();
    esp_err_t ret = nimble_port_stop();
    if (ret != ESP_OK) {
        return ret;
    }
    esp_nimble_deinit();

    ret = esp_blufi_profile_deinit();
    if (ret != ESP_OK) {
        return ret;
    }

    esp_blufi_btc_deinit();
    return ESP_OK;
}

esp_err_t esp_blufi_host_and_cb_init(esp_blufi_callbacks_t *callbacks)
{
    esp_err_t ret = esp_blufi_register_callbacks(callbacks);
    if (ret) {
        return ret;
    }

    return esp_blufi_host_init();
}
#endif

#if CONFIG_BT_CONTROLLER_ENABLED || !CONFIG_BT_NIMBLE_ENABLED
esp_err_t esp_blufi_controller_init(void)
{
#if CONFIG_IDF_TARGET_ESP32
    ESP_ERROR_CHECK(esp_bt_controller_mem_release(ESP_BT_MODE_CLASSIC_BT));
#endif

    esp_bt_controller_config_t bt_cfg = BT_CONTROLLER_INIT_CONFIG_DEFAULT();
    esp_err_t ret = esp_bt_controller_init(&bt_cfg);
    if (ret) {
        return ret;
    }

    ret = esp_bt_controller_enable(ESP_BT_MODE_BLE);
    if (ret) {
        return ret;
    }
    return ESP_OK;
}

esp_err_t esp_blufi_controller_deinit(void)
{
    esp_err_t ret = esp_bt_controller_disable();
    if (ret) {
        return ret;
    }

    return esp_bt_controller_deinit();
}
#endif
