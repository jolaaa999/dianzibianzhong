#include <algorithm>
#include <array>
#include <cctype>
#include <cinttypes>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cerrno>
#include <string>

#include "lwip/err.h"
#include "lwip/sockets.h"
#include "lwip/sys.h"
#include "lwip/netdb.h"
#include "driver/i2c.h"
#include "driver/gpio.h"
#include "driver/uart.h"
#include "esp_err.h"
#include "esp_log.h"
#include "esp_task_wdt.h"
#include "esp_timer.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_http_server.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "nvs_flash.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "sh2.h"
#include "sh2_SensorValue.h"
#include "sh2_err.h"
#include "sh2_hal.h"

namespace {

constexpr const char *TAG = "bno085_link";

// WiFi配置 - 默认值（首次启动使用，之后从NVS读取）
constexpr const char *DEFAULT_WIFI_SSID = "Bianzhong_Stage";
constexpr const char *DEFAULT_WIFI_PASS = "12345678";
constexpr int WIFI_MAX_RETRY = 10;
constexpr const char *PROV_AP_PASS = "12345678";
constexpr int PROV_AP_MAX_CONN = 4;
constexpr const char *PROV_AP_IP = "192.168.4.1";
constexpr const char *PROV_AP_NETMASK = "255.255.255.0";
[[maybe_unused]] char g_captive_portal_uri[32] = "http://192.168.4.1";

// 运行时配置（从NVS加载）
char g_wifi_ssid[32] = {0};
char g_wifi_pass[64] = {0};
char g_prov_service_name[32] = {0};
char g_device_id[20] = {0};  // "AABBCCDDEEFF-H12" = 17 字节，含 NUL
int32_t g_hammer_id = 0;

// UDP配置
constexpr int UDP_PORT = 3333;
constexpr const char *UDP_BROADCAST_IP = "255.255.255.255";

// NVS配置键
constexpr const char *NVS_NAMESPACE = "hammer_cfg";
constexpr const char *NVS_KEY_SSID = "wifi_ssid";
constexpr const char *NVS_KEY_PASS = "wifi_pass";
constexpr const char *NVS_KEY_ID = "hammer_id";
constexpr const char *NVS_KEY_PROVISIONED = "provisioned";

constexpr uart_port_t BNO_UART = UART_NUM_1;
constexpr int BNO_BAUD_DEFAULT = 3000000;
constexpr int BNO_TX_GPIO = 2;
constexpr int BNO_RX_GPIO = 1;
constexpr int UART_BUF_SIZE = 4096;
constexpr uint8_t SLIP_FRAME_DELIM = 0x7E;
constexpr uint8_t SLIP_ESCAPE = 0x7D;
constexpr uint8_t SLIP_ESCAPE_MASK = 0x20;
constexpr uint8_t SLIP_PROTOCOL_BYTE = 0x01;

constexpr i2c_port_t DRV_I2C_PORT = I2C_NUM_0;
constexpr gpio_num_t DRV_I2C_SDA_GPIO = GPIO_NUM_20;
constexpr gpio_num_t DRV_I2C_SCL_GPIO = GPIO_NUM_19;
constexpr uint32_t DRV_I2C_FREQ_HZ = 400000;
constexpr uint8_t DRV2605_ADDR = 0x5A;

constexpr uint8_t DRV_REG_STATUS = 0x00;
constexpr uint8_t DRV_REG_MODE = 0x01;
constexpr uint8_t DRV_REG_RTP_INPUT = 0x02;
constexpr uint8_t DRV_REG_LIBRARY = 0x03;
constexpr uint8_t DRV_REG_WAVESEQ1 = 0x04;
constexpr uint8_t DRV_REG_WAVESEQ2 = 0x05;
constexpr uint8_t DRV_REG_GO = 0x0C;
constexpr uint8_t DRV_REG_FEEDBACK = 0x1A;
constexpr uint8_t DRV_REG_CONTROL3 = 0x1D;

constexpr uint8_t DRV_LIBRARY_ROM = 1;
constexpr uint8_t DRV_EFFECT_STARTUP_PULSE = 1;
constexpr uint8_t DRV_EFFECT_STRIKE_LIGHT = 10;   // Double click 100% - 轻快的双击
constexpr uint8_t DRV_EFFECT_STRIKE_MEDIUM = 14;  // Buzz 1 - 100% - 中等嗡鸣
constexpr uint8_t DRV_EFFECT_STRIKE_HEAVY = 47;   // Long buzz - 100% - 长时间强烈嗡鸣
constexpr uint8_t DRV_EFFECT_FALLBACK = DRV_EFFECT_STARTUP_PULSE;
constexpr uint8_t DRV_MODE_INTTRIG = 0x00;
constexpr uint8_t DRV_FEEDBACK_LRA_BIT = 0x80;
constexpr uint8_t DRV_CONTROL3_ERM_OPEN_LOOP_BIT = 0x20;

constexpr uint32_t BNO_BOOT_SETTLE_MS = 50;
constexpr uint32_t BNO_READ_SLICE_US = 2000;
constexpr uint32_t BNO_INIT_WAIT_US = 1500000;
constexpr uint32_t BNO_POST_RESET_SETTLE_US = 300000;
constexpr uint32_t BNO_STREAM_WAIT_MS = 5000;
constexpr uint32_t BNO_ORIENTATION_INTERVAL_US = 10000;
constexpr uint32_t BNO_LINEAR_ACCEL_INTERVAL_US = 5000;
constexpr uint32_t BNO_PROBE_CAPTURE_MS = 1200;
constexpr size_t BNO_PROBE_RAW_LIMIT = 4096;
constexpr uint64_t NO_SENSOR_LOG_INTERVAL_US = 2000000;
constexpr uint32_t MOTION_TASK_STACK_WORDS = 8192;
constexpr UBaseType_t MOTION_TASK_PRIORITY = 5;
constexpr BaseType_t MOTION_TASK_CORE = 1;
constexpr uint64_t LOG_INTERVAL_US = 500000;
constexpr uint64_t STRIKE_COOLDOWN_US = 220000;
constexpr uint64_t OCTAVE_SCAN_INTERVAL_US = 20000;
constexpr uint64_t OCTAVE_DEBOUNCE_US = 120000;

constexpr gpio_num_t OCTAVE_BUTTON_GPIO_1 = GPIO_NUM_9;
constexpr gpio_num_t OCTAVE_BUTTON_GPIO_2 = GPIO_NUM_10;
constexpr gpio_num_t OCTAVE_BUTTON_GPIO_3 = GPIO_NUM_11;
constexpr gpio_num_t OCTAVE_BUTTON_GPIO_4 = GPIO_NUM_12;

// 方案A改进: 纯角速度检测（虚空挥动，无需真实撞击）
constexpr float ANGULAR_VEL_LIGHT_THRESHOLD = 300.0f;   // 度/秒 - 轻度击打（提高阈值）
constexpr float ANGULAR_VEL_MEDIUM_THRESHOLD = 500.0f;  // 度/秒 - 中度击打
constexpr float ANGULAR_VEL_HEAVY_THRESHOLD = 800.0f;   // 度/秒 - 重度击打
constexpr float SWING_DETECT_THRESHOLD = 250.0f;        // 度/秒 - 开始挥动检测（大幅提高以减少误触发和漂移）
constexpr float ANGULAR_VEL_NOISE_FLOOR = 18.0f;        // 度/秒 - 静止姿态噪声死区
constexpr float ANGULAR_VEL_FILTER_ALPHA = 0.32f;       // 角速度低通，兼顾稳定与响应

bool g_bno_uart_initialized = false;
bool g_drv_ready = false;
uint32_t g_bno_sensor_events = 0;
bool g_bno_reset_seen = false;
int g_bno_baud = BNO_BAUD_DEFAULT;
constexpr std::array<int, 8> BNO_PROBE_BAUDS = {
    115200, 230400, 460800, 921600, 1000000, 1500000, 2000000, 3000000};

// UDP全局变量
int g_udp_sock = -1;
struct sockaddr_in g_dest_addr;
uint64_t g_last_cursor_send_us = 0;
constexpr uint64_t CURSOR_SEND_INTERVAL_US = 33333;  // 30Hz
uint32_t g_haptic_command_count = 0;
uint32_t g_cursor_packets = 0;  // 累计 cursor UDP 包数（≥30Hz 现场验证）
uint64_t g_first_cursor_log_us = 0;   // 第一次发出 cursor 包时的 µs，便于现场核对广播延迟
uint64_t g_udp_start_us = 0;          // init_udp 完成时的 µs，作为首包延迟起点
int g_current_octave = 3;
uint64_t g_last_octave_scan_us = 0;
uint64_t g_last_octave_change_us = 0;
int g_wifi_retry_count = 0;
bool g_sta_connected = false;
bool g_wifi_provisioned = false;
bool g_wifi_started = false;
bool g_softap_active = false;
bool g_should_connect_station = false;
enum class ProvisionUiStage : uint8_t {
    Ready = 0,
    Applying = 1,
    Connecting = 2,
    GettingIp = 3,
    Connected = 4,
    Failed = 5,
};
ProvisionUiStage g_prov_stage = ProvisionUiStage::Ready;
char g_prov_status_message[96] = "等待配网";
uint32_t g_prov_attempt_id = 0;
httpd_handle_t g_prov_http_server = nullptr;
esp_netif_t *g_sta_netif = nullptr;
esp_netif_t *g_ap_netif = nullptr;
TaskHandle_t g_dns_captive_task = nullptr;
int g_dns_captive_sock = -1;

// 函数前向声明
void send_cursor_position(float yaw, float pitch, float roll, uint64_t timestamp_us);
void register_strike(float peak_angular_vel, float accel_mag, uint64_t now_us);
void init_octave_buttons();
void update_octave_buttons(uint64_t now_us);
void stop_udp();
void service_udp_commands();
bool save_config_to_nvs(const char *ssid, const char *pass, int hammer_id);
bool set_provisioned_flag(bool provisioned);
void refresh_prov_service_name();
void start_wifi_provisioning();
void start_softap_provisioning();
void stop_softap_provisioning();
void configure_softap_netif();
void start_dns_captive_portal();
void stop_dns_captive_portal();
void start_wifi_station();
bool apply_wifi_credentials(const char *ssid, const char *password, const char *source);
void init_wifi_provisioning();
std::string url_decode_form_value(const std::string &value);
const char *provision_stage_name(ProvisionUiStage stage);
int provision_stage_progress(ProvisionUiStage stage);
void set_provision_stage(ProvisionUiStage stage, const char *message);
const char *wifi_disconnect_reason_message(uint8_t reason);
void start_provision_timeout_watchdog(uint32_t attempt_id);
esp_err_t handle_http_scan(httpd_req_t *req);
esp_err_t handle_http_root(httpd_req_t *req);
esp_err_t handle_http_provision(httpd_req_t *req);
esp_err_t handle_http_status(httpd_req_t *req);
esp_err_t handle_http_captive_redirect(httpd_req_t *req);
esp_err_t handle_http_404_redirect(httpd_req_t *req, httpd_err_code_t err);

struct SlipParser {
    enum class State {
        WaitStart,
        WaitProtocol,
        InFrame,
        Escape,
    };

    State state = State::WaitStart;
    std::array<uint8_t, SH2_HAL_MAX_TRANSFER_IN> frame = {};
    size_t frame_len = 0;
    uint32_t frame_timestamp_us = 0;
    bool ready = false;
};

struct BnoHalContext {
    sh2_Hal_t hal = {};
    SlipParser parser = {};
    uint32_t rx_frames = 0;
    uint32_t rx_bytes = 0;
    uint32_t tx_frames = 0;
    uint32_t tx_bytes = 0;
    uint16_t last_frame_len = 0;
};

struct BnoProbeResult {
    int baud = 0;
    uint32_t raw_bytes = 0;
    uint32_t shtp_frames = 0;
    uint16_t first_shtp_len = 0;
    bool found_shtp = false;
};

enum class SwingPhase : uint8_t {
    Idle = 0,           // 静止或缓慢移动
    Swinging = 1,       // 检测到挥动（角速度上升，追踪峰值）
    WaitingImpact = 2,  // 未使用（虚空挥动模式不需要）
};

struct MotionState {
    bool has_orientation = false;
    bool has_linear_accel = false;
    float qw = 1.0f;
    float qx = 0.0f;
    float qy = 0.0f;
    float qz = 0.0f;
    float prev_qw = 1.0f;
    float prev_qx = 0.0f;
    float prev_qy = 0.0f;
    float prev_qz = 0.0f;
    float yaw_deg = 0.0f;
    float pitch_deg = 0.0f;
    float roll_deg = 0.0f;
    float prev_yaw_deg = 0.0f;
    float prev_pitch_deg = 0.0f;
    float prev_roll_deg = 0.0f;

    // 角速度历史（用于峰值检测）
    float angular_vel = 0.0f;  // 当前角速度 x[0]
    float angular_vel_prev1 = 0.0f;  // 前一次角速度 x[1]
    float angular_vel_prev2 = 0.0f;  // 前两次角速度 x[2]

    // 角速度导数（角加速度）
    float angular_accel = 0.0f;  // 当前角加速度 dx[0]
    float angular_accel_prev = 0.0f;  // 前一次角加速度 dx[1]

    // 角加速度导数（jerk）
    float angular_jerk = 0.0f;  // ddx[0]

    float peak_angular_vel = 0.0f;  // 本次挥动的角速度峰值
    uint64_t last_orientation_us = 0; // 上次姿态更新时间
    float ax = 0.0f;
    float ay = 0.0f;
    float az = 0.0f;
    float accel_mag = 0.0f;
    SwingPhase swing_phase = SwingPhase::Idle;
    uint64_t last_log_us = 0;
    uint64_t last_no_sensor_log_us = 0;
    uint64_t last_strike_us = 0;
    uint64_t swing_start_us = 0;  // 挥动开始时间
    uint32_t strike_count = 0;
};

enum class StrikeTier : uint8_t {
    Light = 0,
    Medium = 1,
    Heavy = 2,
};

void send_strike_event(float force, StrikeTier tier, float yaw, float pitch, float roll, uint64_t timestamp_us);

enum class DrvPulseResult : uint8_t {
    Ok = 0,
    NotReady = 1,
    ConfigFailed = 2,
    TriggerFailed = 3,
    Busy = 4,
};

BnoHalContext g_bno_hal = {};
BnoProbeResult g_probe_result = {};
MotionState g_motion = {};

void init_drv_i2c()
{
    i2c_config_t cfg = {};
    cfg.mode = I2C_MODE_MASTER;
    cfg.sda_io_num = DRV_I2C_SDA_GPIO;
    cfg.scl_io_num = DRV_I2C_SCL_GPIO;
    cfg.sda_pullup_en = GPIO_PULLUP_ENABLE;
    cfg.scl_pullup_en = GPIO_PULLUP_ENABLE;
    cfg.master.clk_speed = DRV_I2C_FREQ_HZ;

    ESP_ERROR_CHECK(i2c_param_config(DRV_I2C_PORT, &cfg));
    ESP_ERROR_CHECK(i2c_driver_install(DRV_I2C_PORT, cfg.mode, 0, 0, 0));
}

esp_err_t drv_write_reg(uint8_t reg, uint8_t value)
{
    const uint8_t payload[2] = {reg, value};
    return i2c_master_write_to_device(
        DRV_I2C_PORT, DRV2605_ADDR, payload, sizeof(payload), pdMS_TO_TICKS(100));
}

esp_err_t drv_read_reg(uint8_t reg, uint8_t *value)
{
    return i2c_master_write_read_device(
        DRV_I2C_PORT, DRV2605_ADDR, &reg, 1, value, 1, pdMS_TO_TICKS(100));
}

void log_drv_state(const char *reason);
bool configure_drv2605_for_lra();

bool probe_drv2605()
{
    ESP_LOGI(TAG, "Probing DRV2605L at address 0x%02X...", DRV2605_ADDR);

    uint8_t status = 0;
    esp_err_t err = drv_read_reg(DRV_REG_STATUS, &status);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L probe failed at 0x%02X: %s",
                 DRV2605_ADDR, esp_err_to_name(err));
        ESP_LOGW(TAG, "Please check DRV2605L wiring:");
        ESP_LOGW(TAG, "  - VCC connected to 3.3V");
        ESP_LOGW(TAG, "  - GND connected to GND");
        ESP_LOGW(TAG, "  - SDA connected to GPIO%d", DRV_I2C_SDA_GPIO);
        ESP_LOGW(TAG, "  - SCL connected to GPIO%d", DRV_I2C_SCL_GPIO);
        return false;
    }

    uint8_t mode = 0;
    err = drv_read_reg(DRV_REG_MODE, &mode);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L mode read failed: %s", esp_err_to_name(err));
        return false;
    }

    ESP_LOGI(TAG, "DRV2605L detected at 0x%02X, STATUS=0x%02X MODE=0x%02X",
             DRV2605_ADDR, status, mode);

    if (!configure_drv2605_for_lra()) {
        ESP_LOGW(TAG, "DRV2605L base configuration failed");
        return false;
    }

    log_drv_state("configured");
    return true;
}

const char *strike_tier_name(StrikeTier tier)
{
    switch (tier) {
    case StrikeTier::Light:
        return "light";
    case StrikeTier::Medium:
        return "medium";
    case StrikeTier::Heavy:
        return "heavy";
    }

    return "unknown";
}

uint8_t strike_effect_for_tier(StrikeTier tier)
{
    switch (tier) {
    case StrikeTier::Light:
        return DRV_EFFECT_STRIKE_LIGHT;
    case StrikeTier::Medium:
        return DRV_EFFECT_STRIKE_MEDIUM;
    case StrikeTier::Heavy:
        return DRV_EFFECT_STRIKE_HEAVY;
    }

    return DRV_EFFECT_STRIKE_MEDIUM;
}

const char *drv_pulse_result_name(DrvPulseResult result)
{
    switch (result) {
    case DrvPulseResult::Ok:
        return "ok";
    case DrvPulseResult::NotReady:
        return "not_ready";
    case DrvPulseResult::ConfigFailed:
        return "config_failed";
    case DrvPulseResult::TriggerFailed:
        return "trigger_failed";
    case DrvPulseResult::Busy:
        return "busy";
    }

    return "unknown";
}

void log_drv_state(const char *reason)
{
    uint8_t status = 0;
    uint8_t mode = 0;
    uint8_t library = 0;
    uint8_t wave1 = 0;
    uint8_t go = 0;
    uint8_t feedback = 0;
    uint8_t control3 = 0;

    const esp_err_t status_err = drv_read_reg(DRV_REG_STATUS, &status);
    const esp_err_t mode_err = drv_read_reg(DRV_REG_MODE, &mode);
    const esp_err_t library_err = drv_read_reg(DRV_REG_LIBRARY, &library);
    const esp_err_t wave1_err = drv_read_reg(DRV_REG_WAVESEQ1, &wave1);
    const esp_err_t go_err = drv_read_reg(DRV_REG_GO, &go);
    const esp_err_t feedback_err = drv_read_reg(DRV_REG_FEEDBACK, &feedback);
    const esp_err_t control3_err = drv_read_reg(DRV_REG_CONTROL3, &control3);

    ESP_LOGI(
        TAG,
        "DRV2605L %s: ready=%s STATUS=%s:0x%02X MODE=%s:0x%02X LIB=%s:0x%02X WAVE1=%s:0x%02X GO=%s:0x%02X FB=%s:0x%02X CTRL3=%s:0x%02X",
        reason,
        g_drv_ready ? "yes" : "no",
        esp_err_to_name(status_err),
        status,
        esp_err_to_name(mode_err),
        mode,
        esp_err_to_name(library_err),
        library,
        esp_err_to_name(wave1_err),
        wave1,
        esp_err_to_name(go_err),
        go,
        esp_err_to_name(feedback_err),
        feedback,
        esp_err_to_name(control3_err),
        control3);
}

bool configure_drv2605_for_lra()
{
    uint8_t feedback = 0;
    esp_err_t err = drv_read_reg(DRV_REG_FEEDBACK, &feedback);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L feedback read failed: %s", esp_err_to_name(err));
        return false;
    }

    feedback |= DRV_FEEDBACK_LRA_BIT;
    err = drv_write_reg(DRV_REG_FEEDBACK, feedback);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L feedback write failed: %s", esp_err_to_name(err));
        return false;
    }

    uint8_t control3 = 0;
    err = drv_read_reg(DRV_REG_CONTROL3, &control3);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L control3 read failed: %s", esp_err_to_name(err));
        return false;
    }

    control3 &= static_cast<uint8_t>(~DRV_CONTROL3_ERM_OPEN_LOOP_BIT);
    err = drv_write_reg(DRV_REG_CONTROL3, control3);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L control3 write failed: %s", esp_err_to_name(err));
        return false;
    }

    err = drv_write_reg(DRV_REG_MODE, DRV_MODE_INTTRIG);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L mode write failed: %s", esp_err_to_name(err));
        return false;
    }

    err = drv_write_reg(DRV_REG_RTP_INPUT, 0x00);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L RTP reset failed: %s", esp_err_to_name(err));
        return false;
    }

    err = drv_write_reg(DRV_REG_LIBRARY, DRV_LIBRARY_ROM);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L library write failed: %s", esp_err_to_name(err));
        return false;
    }

    return true;
}

StrikeTier strike_tier_for_angular_velocity(float angular_vel_deg_per_sec)
{
    if (angular_vel_deg_per_sec >= ANGULAR_VEL_HEAVY_THRESHOLD) {
        return StrikeTier::Heavy;
    }
    if (angular_vel_deg_per_sec >= ANGULAR_VEL_MEDIUM_THRESHOLD) {
        return StrikeTier::Medium;
    }
    return StrikeTier::Light;
}

DrvPulseResult trigger_drv2605_effect(uint8_t effect_id)
{
    if (!g_drv_ready) {
        ESP_LOGW(TAG, "DRV2605L trigger skipped: g_drv_ready=false");
        return DrvPulseResult::NotReady;
    }

    uint8_t go_before = 0;
    esp_err_t err = drv_read_reg(DRV_REG_GO, &go_before);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L GO read failed before trigger: %s", esp_err_to_name(err));
        return DrvPulseResult::ConfigFailed;
    }
    if (go_before != 0) {
        ESP_LOGW(TAG, "DRV2605L busy before trigger, GO=0x%02X", go_before);
        return DrvPulseResult::Busy;
    }

    err = drv_write_reg(DRV_REG_MODE, DRV_MODE_INTTRIG);
    if (err == ESP_OK) {
        err = drv_write_reg(DRV_REG_LIBRARY, DRV_LIBRARY_ROM);
    }
    if (err == ESP_OK) {
        err = drv_write_reg(DRV_REG_WAVESEQ1, effect_id);
    }
    if (err == ESP_OK) {
        err = drv_write_reg(DRV_REG_WAVESEQ2, 0);
    }
    if (err == ESP_OK) {
        err = drv_write_reg(DRV_REG_GO, 1);
    }

    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L strike pulse failed: %s", esp_err_to_name(err));
        log_drv_state("trigger_write_failed");
        return DrvPulseResult::TriggerFailed;
    }

    uint8_t go_after = 0;
    err = drv_read_reg(DRV_REG_GO, &go_after);
    if (err != ESP_OK) {
        ESP_LOGW(TAG, "DRV2605L GO read failed after trigger: %s", esp_err_to_name(err));
        return DrvPulseResult::TriggerFailed;
    }
    if (go_after == 0) {
        ESP_LOGW(TAG, "DRV2605L GO did not latch for effect %u", effect_id);
        log_drv_state("go_not_latched");
        return DrvPulseResult::TriggerFailed;
    }

    return DrvPulseResult::Ok;
}

const char *skip_json_key_value(const char *json, const char *key)
{
    char pattern[32] = {};
    snprintf(pattern, sizeof(pattern), "\"%s\":", key);
    const char *cursor = strstr(json, pattern);
    if (cursor == nullptr) {
        return nullptr;
    }
    return cursor + strlen(pattern);
}

bool parse_json_int_value(const char *json, const char *key, int *value)
{
    const char *cursor = skip_json_key_value(json, key);
    if (cursor == nullptr) {
        return false;
    }
    return sscanf(cursor, "%d", value) == 1;
}

bool parse_json_float_value(const char *json, const char *key, float *value)
{
    const char *cursor = skip_json_key_value(json, key);
    if (cursor == nullptr) {
        return false;
    }
    return sscanf(cursor, "%f", value) == 1;
}

bool is_haptic_command_json(const char *json)
{
    return strstr(json, "\"type\":\"haptic\"") != nullptr;
}

bool handle_haptic_command_json(const char *json)
{
    if (!is_haptic_command_json(json)) {
        return false;
    }

    int target_hammer_id = 0;
    if (!parse_json_int_value(json, "id", &target_hammer_id) ||
        target_hammer_id != g_hammer_id) {
        return false;
    }

    int tier = 0;
    int bell_id = 0;
    float intensity = 0.0f;
    parse_json_int_value(json, "tier", &tier);
    parse_json_int_value(json, "bellId", &bell_id);
    parse_json_float_value(json, "intensity", &intensity);

    tier = std::clamp(tier, 1, 3);
    intensity = std::clamp(intensity, 0.0f, 1.0f);
    const StrikeTier strike_tier = tier == 3
        ? StrikeTier::Heavy
        : (tier == 2 ? StrikeTier::Medium : StrikeTier::Light);
    const uint8_t effect_id = strike_effect_for_tier(strike_tier);

    DrvPulseResult pulse_result = trigger_drv2605_effect(effect_id);
    bool used_fallback = false;
    if (pulse_result != DrvPulseResult::Ok && pulse_result != DrvPulseResult::NotReady) {
        pulse_result = trigger_drv2605_effect(DRV_EFFECT_FALLBACK);
        used_fallback = (pulse_result == DrvPulseResult::Ok);
    }

    ++g_haptic_command_count;
    ESP_LOGI(TAG,
             "haptic cmd #%" PRIu32 " bell=%d tier=%s intensity=%.2f effect=%u pulse=%s fallback=%s",
             g_haptic_command_count,
             bell_id,
             strike_tier_name(strike_tier),
             intensity,
             effect_id,
             drv_pulse_result_name(pulse_result),
             used_fallback ? "yes" : "no");
    return true;
}

void init_bno_uart()
{
    uart_config_t cfg = {};
    cfg.baud_rate = g_bno_baud;
    cfg.data_bits = UART_DATA_8_BITS;
    cfg.parity = UART_PARITY_DISABLE;
    cfg.stop_bits = UART_STOP_BITS_1;
    cfg.flow_ctrl = UART_HW_FLOWCTRL_DISABLE;
    cfg.source_clk = UART_SCLK_DEFAULT;

    if (!g_bno_uart_initialized) {
        ESP_ERROR_CHECK(uart_driver_install(BNO_UART, UART_BUF_SIZE, 0, 0, nullptr, 0));
        ESP_ERROR_CHECK(uart_param_config(BNO_UART, &cfg));
        ESP_ERROR_CHECK(uart_set_pin(
            BNO_UART, BNO_TX_GPIO, BNO_RX_GPIO,
            UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));
        g_bno_uart_initialized = true;
    } else {
        ESP_ERROR_CHECK(uart_set_baudrate(BNO_UART, g_bno_baud));
    }

    ESP_ERROR_CHECK(uart_flush_input(BNO_UART));
}

void set_bno_uart_baud(int baud)
{
    g_bno_baud = baud;
    init_bno_uart();
}

void log_bno_uart_stats(const char *reason)
{
    ESP_LOGI(TAG,
             "%s: baud=%d sensor_events=%" PRIu32 " rx_frames=%" PRIu32 " rx_bytes=%" PRIu32 " tx_frames=%" PRIu32 " last_frame_len=%u uart_ready=%s reset=%s",
             reason,
             g_bno_baud,
             g_bno_sensor_events,
             g_bno_hal.rx_frames,
             g_bno_hal.rx_bytes,
             g_bno_hal.tx_frames,
             g_bno_hal.last_frame_len,
             g_bno_uart_initialized ? "yes" : "no",
             g_bno_reset_seen ? "yes" : "no");
}

void reset_slip_parser(SlipParser *parser)
{
    parser->state = SlipParser::State::WaitStart;
    parser->frame_len = 0;
    parser->frame_timestamp_us = 0;
    parser->ready = false;
}

bool is_valid_shtp_frame(const uint8_t *frame, size_t len)
{
    if (len < 4) {
        return false;
    }

    const uint16_t total_len =
        static_cast<uint16_t>(frame[0]) | (static_cast<uint16_t>(frame[1]) << 8);
    return (total_len & 0x7FFFu) == len;
}

bool push_slip_byte(SlipParser *parser, uint8_t byte, uint32_t timestamp_us)
{
    switch (parser->state) {
    case SlipParser::State::WaitStart:
        if (byte == SLIP_FRAME_DELIM) {
            parser->state = SlipParser::State::WaitProtocol;
            parser->frame_len = 0;
        }
        break;
    case SlipParser::State::WaitProtocol:
        if (byte == SLIP_FRAME_DELIM) {
            break;
        }
        if (byte != SLIP_PROTOCOL_BYTE) {
            reset_slip_parser(parser);
            break;
        }
        parser->state = SlipParser::State::InFrame;
        break;
    case SlipParser::State::InFrame:
        if (byte == SLIP_FRAME_DELIM) {
            if (parser->frame_len > 0) {
                parser->ready = true;
                parser->frame_timestamp_us = timestamp_us;
                parser->state = SlipParser::State::WaitStart;
                return true;
            }
            parser->state = SlipParser::State::WaitStart;
            break;
        }
        if (byte == SLIP_ESCAPE) {
            parser->state = SlipParser::State::Escape;
            break;
        }
        if (parser->frame_len >= parser->frame.size()) {
            reset_slip_parser(parser);
            break;
        }
        parser->frame[parser->frame_len++] = byte;
        break;
    case SlipParser::State::Escape:
        byte ^= SLIP_ESCAPE_MASK;
        if (parser->frame_len >= parser->frame.size()) {
            reset_slip_parser(parser);
            break;
        }
        parser->frame[parser->frame_len++] = byte;
        parser->state = SlipParser::State::InFrame;
        break;
    }

    return false;
}

void send_bno_soft_reset()
{
    const uint8_t soft_reset_pkt[] = {0x7E, 0x01, 0x05, 0x00, 0x01, 0x00, 0x01, 0x7E};
    for (uint8_t byte : soft_reset_pkt) {
        uart_write_bytes(BNO_UART, reinterpret_cast<const char *>(&byte), 1);
        uart_wait_tx_done(BNO_UART, pdMS_TO_TICKS(20));
        vTaskDelay(pdMS_TO_TICKS(1));
    }
}

void format_preview(const uint8_t *data, size_t len, char *out, size_t out_len)
{
    if (out_len == 0) {
        return;
    }
    out[0] = '\0';
    size_t cursor = 0;
    const size_t preview_len = std::min(len, static_cast<size_t>(12));
    for (size_t i = 0; i < preview_len && cursor + 4 < out_len; ++i) {
        const int written = snprintf(out + cursor, out_len - cursor, "%02X ", data[i]);
        if (written <= 0) {
            break;
        }
        cursor += static_cast<size_t>(written);
    }
}

BnoProbeResult probe_single_bno_baud(int baud)
{
    BnoProbeResult result = {};
    result.baud = baud;
    SlipParser parser = {};
    static std::array<uint8_t, BNO_PROBE_RAW_LIMIT> raw = {};
    static std::array<uint8_t, 64> rx_chunk = {};
    size_t raw_len = 0;

    set_bno_uart_baud(baud);
    reset_slip_parser(&parser);
    vTaskDelay(pdMS_TO_TICKS(BNO_BOOT_SETTLE_MS));
    send_bno_soft_reset();

    const int64_t deadline_us =
        esp_timer_get_time() + (static_cast<int64_t>(BNO_PROBE_CAPTURE_MS) * 1000);
    while (esp_timer_get_time() < deadline_us) {
        size_t buffered = 0;
        ESP_ERROR_CHECK(uart_get_buffered_data_len(BNO_UART, &buffered));
        if (buffered == 0) {
            vTaskDelay(pdMS_TO_TICKS(2));
            continue;
        }

        const size_t chunk_len = std::min(buffered, rx_chunk.size());
        const int read = uart_read_bytes(BNO_UART, rx_chunk.data(), chunk_len, pdMS_TO_TICKS(10));
        if (read <= 0) {
            continue;
        }

        result.raw_bytes += static_cast<uint32_t>(read);
        const size_t copy_len =
            std::min(static_cast<size_t>(read), raw.size() - std::min(raw_len, raw.size()));
        if (copy_len > 0 && raw_len < raw.size()) {
            memcpy(raw.data() + raw_len, rx_chunk.data(), copy_len);
            raw_len += copy_len;
        }

        const uint32_t now_us = static_cast<uint32_t>(esp_timer_get_time());
        for (int i = 0; i < read; ++i) {
            if (push_slip_byte(&parser, rx_chunk[i], now_us) && parser.ready) {
                if (is_valid_shtp_frame(parser.frame.data(), parser.frame_len)) {
                    ++result.shtp_frames;
                    result.first_shtp_len = static_cast<uint16_t>(parser.frame_len);
                }
                parser.ready = false;
                parser.frame_len = 0;
            }
        }
    }

    result.found_shtp = result.shtp_frames > 0;
    char preview[64] = {};
    format_preview(raw.data(), raw_len, preview, sizeof(preview));
    ESP_LOGI(TAG,
             "BNO probe baud=%d raw_bytes=%" PRIu32 " shtp_frames=%" PRIu32 " first_shtp_len=%u preview=%s",
             result.baud,
             result.raw_bytes,
             result.shtp_frames,
             result.first_shtp_len,
             preview[0] == '\0' ? "(none)" : preview);

    uart_flush_input(BNO_UART);
    return result;
}

BnoProbeResult probe_bno_protocols()
{
    BnoProbeResult best = {};
    for (int baud : BNO_PROBE_BAUDS) {
        const BnoProbeResult current = probe_single_bno_baud(baud);
        if (current.found_shtp) {
            return current;
        }
        if (current.raw_bytes > best.raw_bytes) {
            best = current;
        }
    }
    return best;
}

int send_slip_transfer(const uint8_t *payload, unsigned len)
{
    std::array<uint8_t, (SH2_HAL_MAX_TRANSFER_OUT * 2) + 3> tx = {};
    size_t cursor = 0;
    tx[cursor++] = SLIP_FRAME_DELIM;
    tx[cursor++] = SLIP_PROTOCOL_BYTE;

    for (unsigned i = 0; i < len; ++i) {
        const uint8_t byte = payload[i];
        if (byte == SLIP_FRAME_DELIM || byte == SLIP_ESCAPE) {
            tx[cursor++] = SLIP_ESCAPE;
            tx[cursor++] = byte ^ SLIP_ESCAPE_MASK;
        } else {
            tx[cursor++] = byte;
        }
    }
    tx[cursor++] = SLIP_FRAME_DELIM;

    int written = 0;
    for (size_t i = 0; i < cursor; ++i) {
        const int rc = uart_write_bytes(BNO_UART, reinterpret_cast<const char *>(&tx[i]), 1);
        if (rc > 0) {
            written += rc;
        }
        uart_wait_tx_done(BNO_UART, pdMS_TO_TICKS(20));
        vTaskDelay(pdMS_TO_TICKS(1));
    }

    if (written > 0) {
        ++g_bno_hal.tx_frames;
        g_bno_hal.tx_bytes += static_cast<uint32_t>(written);
    }
    return written > 0 ? static_cast<int>(len) : written;
}

int bno_hal_open(sh2_Hal_t *self)
{
    auto *ctx = reinterpret_cast<BnoHalContext *>(self);
    reset_slip_parser(&ctx->parser);
    ctx->rx_frames = 0;
    ctx->rx_bytes = 0;
    ctx->tx_frames = 0;
    ctx->tx_bytes = 0;
    ctx->last_frame_len = 0;
    g_bno_reset_seen = false;
    g_bno_sensor_events = 0;

    vTaskDelay(pdMS_TO_TICKS(BNO_BOOT_SETTLE_MS));
    send_bno_soft_reset();
    ++ctx->tx_frames;
    ctx->tx_bytes += 8;
    ESP_LOGI(TAG, "Sent BNO085 soft reset on UART%d @ %d bps", BNO_UART, g_bno_baud);
    return 0;
}

void bno_hal_close(sh2_Hal_t *self)
{
    auto *ctx = reinterpret_cast<BnoHalContext *>(self);
    reset_slip_parser(&ctx->parser);
    uart_flush_input(BNO_UART);
}

int bno_hal_read(sh2_Hal_t *self, uint8_t *buffer, unsigned len, uint32_t *t_us)
{
    auto *ctx = reinterpret_cast<BnoHalContext *>(self);

    if (ctx->parser.ready) {
        const size_t copy_len = std::min(static_cast<size_t>(len), ctx->parser.frame_len);
        memcpy(buffer, ctx->parser.frame.data(), copy_len);
        *t_us = ctx->parser.frame_timestamp_us;
        ctx->parser.ready = false;
        ctx->parser.frame_len = 0;
        return static_cast<int>(copy_len);
    }

    std::array<uint8_t, 64> rx_chunk = {};
    const int64_t deadline_us = esp_timer_get_time() + BNO_READ_SLICE_US;
    while (esp_timer_get_time() < deadline_us) {
        size_t buffered = 0;
        ESP_ERROR_CHECK(uart_get_buffered_data_len(BNO_UART, &buffered));
        if (buffered == 0) {
            break;
        }

        const size_t chunk_len = std::min(buffered, rx_chunk.size());
        const int read = uart_read_bytes(BNO_UART, rx_chunk.data(), chunk_len, 0);
        if (read <= 0) {
            break;
        }

        ctx->rx_bytes += static_cast<uint32_t>(read);
        const uint32_t now_us = static_cast<uint32_t>(esp_timer_get_time());
        for (int i = 0; i < read; ++i) {
            if (push_slip_byte(&ctx->parser, rx_chunk[i], now_us) && ctx->parser.ready) {
                ++ctx->rx_frames;
                ctx->last_frame_len = static_cast<uint16_t>(ctx->parser.frame_len);
                const size_t copy_len = std::min(static_cast<size_t>(len), ctx->parser.frame_len);
                memcpy(buffer, ctx->parser.frame.data(), copy_len);
                *t_us = ctx->parser.frame_timestamp_us;
                ctx->parser.ready = false;
                ctx->parser.frame_len = 0;
                return static_cast<int>(copy_len);
            }
        }
    }

    return 0;
}

int bno_hal_write(sh2_Hal_t *self, uint8_t *buffer, unsigned len)
{
    (void)self;
    return send_slip_transfer(buffer, len);
}

uint32_t bno_hal_get_time_us(sh2_Hal_t *self)
{
    (void)self;
    return static_cast<uint32_t>(esp_timer_get_time());
}

void quaternion_to_euler(float w, float x, float y, float z,
                         float *yaw_deg, float *pitch_deg, float *roll_deg)
{
    const float sinr_cosp = 2.0f * ((w * x) + (y * z));
    const float cosr_cosp = 1.0f - (2.0f * ((x * x) + (y * y)));
    const float roll = std::atan2(sinr_cosp, cosr_cosp);

    const float sinp = 2.0f * ((w * y) - (z * x));
    const float pitch = std::abs(sinp) >= 1.0f
        ? std::copysign(static_cast<float>(M_PI) / 2.0f, sinp)
        : std::asin(sinp);

    const float siny_cosp = 2.0f * ((w * z) + (x * y));
    const float cosy_cosp = 1.0f - (2.0f * ((y * y) + (z * z)));
    const float yaw = std::atan2(siny_cosp, cosy_cosp);

    constexpr float kRadToDeg = 57.2957795f;
    *yaw_deg = yaw * kRadToDeg;
    *pitch_deg = pitch * kRadToDeg;
    *roll_deg = roll * kRadToDeg;
}

float normalize_signed_degrees_360(float degrees)
{
    while (degrees <= -180.0f) degrees += 360.0f;
    while (degrees > 180.0f) degrees -= 360.0f;
    return degrees;
}

void normalize_quaternion(float *w, float *x, float *y, float *z)
{
    const float magnitude = std::sqrt((*w * *w) + (*x * *x) + (*y * *y) + (*z * *z));
    if (magnitude <= 1e-6f) {
        *w = 1.0f;
        *x = 0.0f;
        *y = 0.0f;
        *z = 0.0f;
        return;
    }

    *w /= magnitude;
    *x /= magnitude;
    *y /= magnitude;
    *z /= magnitude;
}

float quaternion_dot(
    float left_w, float left_x, float left_y, float left_z,
    float right_w, float right_x, float right_y, float right_z)
{
    return (left_w * right_w) + (left_x * right_x) + (left_y * right_y) + (left_z * right_z);
}

float quaternion_delta_degrees(
    float prev_w, float prev_x, float prev_y, float prev_z,
    float curr_w, float curr_x, float curr_y, float curr_z)
{
    normalize_quaternion(&prev_w, &prev_x, &prev_y, &prev_z);
    normalize_quaternion(&curr_w, &curr_x, &curr_y, &curr_z);
    float dot = prev_w * curr_w + prev_x * curr_x + prev_y * curr_y + prev_z * curr_z;
    dot = std::clamp(std::abs(dot), 0.0f, 1.0f);
    const float radians = 2.0f * std::acos(dot);
    return radians * 57.2957795f;
}

const char *swing_phase_name(SwingPhase phase)
{
    switch (phase) {
    case SwingPhase::Idle:
        return "idle";
    case SwingPhase::Swinging:
        return "swinging";
    case SwingPhase::WaitingImpact:
        return "waiting_impact";
    }
    return "unknown";
}

void maybe_log_motion(uint64_t now_us)
{
    if (!g_motion.has_orientation || !g_motion.has_linear_accel) {
        return;
    }

    // 发送光标位置（30Hz）
    if ((now_us - g_last_cursor_send_us) >= CURSOR_SEND_INTERVAL_US) {
        g_last_cursor_send_us = now_us;
        ++g_cursor_packets; // 现场可观测 UDP 实际上行频率
        if (g_first_cursor_log_us == 0) {
            const uint64_t since_start_us =
                (g_udp_start_us > 0) ? (now_us - g_udp_start_us) : 0;
            ESP_LOGI(TAG,
                     "First cursor broadcast sent after udp_init +%" PRIu64 "ms (device=%s)",
                     since_start_us / 1000, g_device_id);
            g_first_cursor_log_us = now_us;
        }
        const uint64_t pose_timestamp_us =
            g_motion.last_orientation_us > 0 ? g_motion.last_orientation_us : now_us;
        send_cursor_position(
            g_motion.yaw_deg,
            g_motion.pitch_deg,
            g_motion.roll_deg,
            pose_timestamp_us);
    }

    if ((now_us - g_motion.last_log_us) < LOG_INTERVAL_US) {
        return;
    }

    g_motion.last_log_us = now_us;
    ESP_LOGI(TAG,
             "pose yaw=%.1f pitch=%.1f roll=%.1f | ang_vel=%.1f°/s peak_vel=%.1f°/s | accel_mag=%.2f | phase=%s strikes=%" PRIu32 " cursor_pkts=%" PRIu32,
             g_motion.yaw_deg,
             g_motion.pitch_deg,
             g_motion.roll_deg,
             g_motion.angular_vel,
             g_motion.peak_angular_vel,
             g_motion.accel_mag,
             swing_phase_name(g_motion.swing_phase),
             g_motion.strike_count,
             g_cursor_packets);
}

void maybe_log_sensor_wait(uint64_t now_us)
{
    if (g_bno_sensor_events > 0) {
        return;
    }
    if ((now_us - g_motion.last_no_sensor_log_us) < NO_SENSOR_LOG_INTERVAL_US) {
        return;
    }

    g_motion.last_no_sensor_log_us = now_us;
    log_bno_uart_stats("No decoded BNO085 sensor event yet");
}

void update_orientation_from_value(const sh2_SensorValue_t &value)
{
    const float prev_qw = g_motion.qw;
    const float prev_qx = g_motion.qx;
    const float prev_qy = g_motion.qy;
    const float prev_qz = g_motion.qz;

    g_motion.prev_yaw_deg = g_motion.yaw_deg;
    g_motion.prev_pitch_deg = g_motion.pitch_deg;
    g_motion.prev_roll_deg = g_motion.roll_deg;

    if (value.sensorId == SH2_ROTATION_VECTOR) {
        g_motion.qx = value.un.rotationVector.i;
        g_motion.qy = value.un.rotationVector.j;
        g_motion.qz = value.un.rotationVector.k;
        g_motion.qw = value.un.rotationVector.real;
    } else {
        g_motion.qx = value.un.gameRotationVector.i;
        g_motion.qy = value.un.gameRotationVector.j;
        g_motion.qz = value.un.gameRotationVector.k;
        g_motion.qw = value.un.gameRotationVector.real;
    }
    normalize_quaternion(&g_motion.qw, &g_motion.qx, &g_motion.qy, &g_motion.qz);

    if (g_motion.has_orientation &&
        quaternion_dot(prev_qw, prev_qx, prev_qy, prev_qz,
                       g_motion.qw, g_motion.qx, g_motion.qy, g_motion.qz) < 0.0f) {
        g_motion.qw = -g_motion.qw;
        g_motion.qx = -g_motion.qx;
        g_motion.qy = -g_motion.qy;
        g_motion.qz = -g_motion.qz;
    }

    const uint64_t now_us = value.timestamp;
    quaternion_to_euler(
        g_motion.qw,
        g_motion.qx,
        g_motion.qy,
        g_motion.qz,
        &g_motion.yaw_deg,
        &g_motion.pitch_deg,
        &g_motion.roll_deg);
    g_motion.yaw_deg = normalize_signed_degrees_360(g_motion.yaw_deg);
    g_motion.pitch_deg = normalize_signed_degrees_360(g_motion.pitch_deg);
    g_motion.roll_deg = normalize_signed_degrees_360(g_motion.roll_deg);

    if (g_motion.has_orientation && g_motion.last_orientation_us > 0) {
        const uint64_t dt_us = now_us - g_motion.last_orientation_us;
        if (dt_us > 0) {
            const float dt_sec = dt_us / 1000000.0f;
            const float orientation_delta = quaternion_delta_degrees(
                prev_qw, prev_qx, prev_qy, prev_qz,
                g_motion.qw, g_motion.qx, g_motion.qy, g_motion.qz);
            float raw_angular_vel = orientation_delta / dt_sec;
            if (raw_angular_vel < ANGULAR_VEL_NOISE_FLOOR) {
                raw_angular_vel = 0.0f;
            }

            g_motion.angular_vel_prev2 = g_motion.angular_vel_prev1;
            g_motion.angular_vel_prev1 = g_motion.angular_vel;
            if (g_motion.angular_vel_prev1 <= ANGULAR_VEL_NOISE_FLOOR && raw_angular_vel == 0.0f) {
                g_motion.angular_vel = 0.0f;
            } else {
                g_motion.angular_vel =
                    (g_motion.angular_vel_prev1 * (1.0f - ANGULAR_VEL_FILTER_ALPHA)) +
                    (raw_angular_vel * ANGULAR_VEL_FILTER_ALPHA);
                if (g_motion.angular_vel < (ANGULAR_VEL_NOISE_FLOOR * 0.5f)) {
                    g_motion.angular_vel = 0.0f;
                }
            }

            g_motion.angular_accel_prev = g_motion.angular_accel;
            g_motion.angular_accel = (g_motion.angular_vel - g_motion.angular_vel_prev1) / dt_sec;
            g_motion.angular_jerk =
                (g_motion.angular_vel_prev2 - 2.0f * g_motion.angular_vel_prev1 + g_motion.angular_vel) /
                (dt_sec * dt_sec);
        }
    }

    g_motion.last_orientation_us = now_us;
    g_motion.has_orientation = true;
    g_motion.prev_qw = prev_qw;
    g_motion.prev_qx = prev_qx;
    g_motion.prev_qy = prev_qy;
    g_motion.prev_qz = prev_qz;

    const bool vel_above_threshold = (g_motion.angular_vel > SWING_DETECT_THRESHOLD);
    const bool is_peak = ((g_motion.angular_accel_prev >= 0.0f && g_motion.angular_accel < 0.0f) ||
                          (g_motion.angular_accel_prev > 0.0f && g_motion.angular_accel <= 0.0f));
    const bool cooldown_ok = ((now_us - g_motion.last_strike_us) >= STRIKE_COOLDOWN_US);

    if (vel_above_threshold && is_peak && cooldown_ok) {
        register_strike(g_motion.angular_vel, 0.0f, now_us);
    }
}

void update_linear_accel_from_value(const sh2_SensorValue_t &value)
{
    g_motion.ax = value.un.linearAcceleration.x;
    g_motion.ay = value.un.linearAcceleration.y;
    g_motion.az = value.un.linearAcceleration.z;
    g_motion.accel_mag = std::sqrt(
        (g_motion.ax * g_motion.ax) +
        (g_motion.ay * g_motion.ay) +
        (g_motion.az * g_motion.az));
    g_motion.has_linear_accel = true;

    maybe_log_motion(value.timestamp);
}

void bno_sensor_callback(void *cookie, sh2_SensorEvent_t *event)
{
    (void)cookie;

    sh2_SensorValue_t value = {};
    if (sh2_decodeSensorEvent(&value, event) != SH2_OK) {
        return;
    }

    ++g_bno_sensor_events;
    if (g_bno_sensor_events <= 8) {
        ESP_LOGI(TAG,
                 "BNO085 sensor event #%" PRIu32 " id=%u timestamp=%" PRIu64,
                 g_bno_sensor_events,
                 value.sensorId,
                 value.timestamp);
    }

    switch (value.sensorId) {
    case SH2_ROTATION_VECTOR:
    case SH2_GAME_ROTATION_VECTOR:
        update_orientation_from_value(value);
        break;
    case SH2_LINEAR_ACCELERATION:
        update_linear_accel_from_value(value);
        break;
    default:
        break;
    }
}

void bno_event_callback(void *cookie, sh2_AsyncEvent_t *event)
{
    (void)cookie;

    switch (event->eventId) {
    case SH2_RESET:
        g_bno_reset_seen = true;
        ESP_LOGI(TAG, "BNO085 reset complete");
        break;
    case SH2_SHTP_EVENT:
        ESP_LOGW(TAG, "BNO085 SHTP event=%u", event->shtpEvent);
        break;
    case SH2_GET_FEATURE_RESP:
        ESP_LOGI(TAG,
                 "feature ready sensor=%u interval=%" PRIu32 "us",
                 event->sh2SensorConfigResp.sensorId,
                 event->sh2SensorConfigResp.sensorConfig.reportInterval_us);
        break;
    default:
        break;
    }
}

bool wait_for_bno_bootstrap()
{
    const uint64_t deadline_us = static_cast<uint64_t>(esp_timer_get_time()) + BNO_INIT_WAIT_US;
    while (static_cast<uint64_t>(esp_timer_get_time()) < deadline_us) {
        sh2_service();
        if (g_bno_reset_seen) {
            const uint64_t settle_deadline_us =
                static_cast<uint64_t>(esp_timer_get_time()) + BNO_POST_RESET_SETTLE_US;
            while (static_cast<uint64_t>(esp_timer_get_time()) < settle_deadline_us) {
                sh2_service();
                vTaskDelay(pdMS_TO_TICKS(1));
            }
            log_bno_uart_stats("BNO085 bootstrap complete");
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(1));
    }

    log_bno_uart_stats("BNO085 bootstrap timeout");
    return false;
}

bool enable_sensor(sh2_SensorId_t sensor_id, uint32_t interval_us)
{
    sh2_SensorConfig_t config = {};
    config.reportInterval_us = interval_us;

    const int rc = sh2_setSensorConfig(sensor_id, &config);
    if (rc != SH2_OK) {
        ESP_LOGE(TAG, "Failed to enable sensor %u, rc=%d", sensor_id, rc);
        return false;
    }

    ESP_LOGI(TAG, "Enabled sensor %u @ %" PRIu32 "us", sensor_id, interval_us);
    return true;
}

bool wait_for_bno_stream()
{
    const int64_t deadline_us =
        esp_timer_get_time() + (static_cast<int64_t>(BNO_STREAM_WAIT_MS) * 1000);
    while (esp_timer_get_time() < deadline_us) {
        sh2_service();
        if (g_motion.has_orientation || g_motion.has_linear_accel) {
            return true;
        }
        vTaskDelay(pdMS_TO_TICKS(2));
    }
    return false;
}

void register_strike(float peak_angular_vel, float accel_mag, uint64_t now_us)
{
    ++g_motion.strike_count;
    g_motion.last_strike_us = now_us;

    // 重置挥动状态
    g_motion.swing_phase = SwingPhase::Idle;
    g_motion.peak_angular_vel = 0.0f;

    const StrikeTier tier = strike_tier_for_angular_velocity(peak_angular_vel);
    ESP_LOGI(TAG,
             "strike #%" PRIu32 " tier=%s peak_ang_vel=%.1f°/s accel=%.2f yaw=%.1f pitch=%.1f",
             g_motion.strike_count,
             strike_tier_name(tier),
             peak_angular_vel,
             accel_mag,
             g_motion.yaw_deg,
             g_motion.pitch_deg);

    // 终端命中正鼓音/侧鼓音成功后，再回发 haptic 指令给击锤。
    float force = (peak_angular_vel - ANGULAR_VEL_LIGHT_THRESHOLD) /
                  (ANGULAR_VEL_HEAVY_THRESHOLD - ANGULAR_VEL_LIGHT_THRESHOLD);
    force = std::max(0.0f, std::min(1.0f, force));
    send_strike_event(force, tier, g_motion.yaw_deg, g_motion.pitch_deg, g_motion.roll_deg, now_us);
}

bool init_bno_motion_pipeline()
{
    g_probe_result = probe_bno_protocols();
    if (!g_probe_result.found_shtp) {
        ESP_LOGE(TAG,
                 "No valid UART-SHTP frame detected, raw_bytes=%" PRIu32,
                 g_probe_result.raw_bytes);
        ESP_LOGE(TAG, "Expected BNO085 UART-SHTP wiring: TX->GPIO%d RX->GPIO%d, PS0->3.3V PS1->GND",
                 BNO_RX_GPIO, BNO_TX_GPIO);
        return false;
    }

    g_bno_baud = g_probe_result.baud;
    init_bno_uart();
    g_bno_sensor_events = 0;
    g_bno_reset_seen = false;

    g_bno_hal.hal.open = bno_hal_open;
    g_bno_hal.hal.close = bno_hal_close;
    g_bno_hal.hal.read = bno_hal_read;
    g_bno_hal.hal.write = bno_hal_write;
    g_bno_hal.hal.getTimeUs = bno_hal_get_time_us;

    int rc = sh2_open(&g_bno_hal.hal, bno_event_callback, nullptr);
    if (rc != SH2_OK) {
        ESP_LOGE(TAG, "sh2_open failed, rc=%d", rc);
        return false;
    }

    rc = sh2_setSensorCallback(bno_sensor_callback, nullptr);
    if (rc != SH2_OK) {
        ESP_LOGE(TAG, "sh2_setSensorCallback failed, rc=%d", rc);
        sh2_close();
        return false;
    }

    if (!wait_for_bno_bootstrap() && g_bno_hal.rx_frames == 0) {
        ESP_LOGE(TAG, "BNO085 produced no valid UART-SHTP frame after startup");
        sh2_close();
        return false;
    }

    rc = sh2_reinitialize();
    if (rc != SH2_OK) {
        ESP_LOGW(TAG, "sh2_reinitialize failed, rc=%d", rc);
    } else {
        ESP_LOGI(TAG, "BNO085 system initialize command acknowledged");
    }

    if (!enable_sensor(SH2_GAME_ROTATION_VECTOR, BNO_ORIENTATION_INTERVAL_US) ||
        !enable_sensor(SH2_LINEAR_ACCELERATION, BNO_LINEAR_ACCEL_INTERVAL_US)) {
        sh2_close();
        return false;
    }

    if (!wait_for_bno_stream()) {
        ESP_LOGW(TAG, "BNO085 stream wait timeout after enabling sensors");
    }

    ESP_LOGI(TAG, "BNO085 motion pipeline ready in UART-SHTP mode @ %d bps", g_bno_baud);
    return true;
}

void motion_task(void *arg)
{
    ESP_LOGI(TAG, "BNO085 + DRV2605L motion-link test");
    ESP_LOGI(TAG,
             "BNO085 wiring: ESP32 TX/GPIO%d -> BNO085 RX, ESP32 RX/GPIO%d <- BNO085 TX, UART-SHTP auto-probe",
             BNO_TX_GPIO,
             BNO_RX_GPIO);
    ESP_LOGI(TAG, "DRV2605L wiring: SDA -> GPIO%d, SCL -> GPIO%d, addr=0x%02X",
             DRV_I2C_SDA_GPIO,
             DRV_I2C_SCL_GPIO,
             DRV2605_ADDR);
    ESP_LOGI(TAG,
             "Strike detection: pure angular velocity (air swing mode), swing_detect=%.1f°/s, cooldown=%" PRIu64 "us",
             SWING_DETECT_THRESHOLD,
             STRIKE_COOLDOWN_US);
    ESP_LOGI(TAG,
             "Strike tiers: light %.1f-%.1f°/s -> effect %u, medium %.1f-%.1f°/s -> effect %u, heavy >=%.1f°/s -> effect %u",
             ANGULAR_VEL_LIGHT_THRESHOLD,
             ANGULAR_VEL_MEDIUM_THRESHOLD - 0.1f,
             DRV_EFFECT_STRIKE_LIGHT,
             ANGULAR_VEL_MEDIUM_THRESHOLD,
             ANGULAR_VEL_HEAVY_THRESHOLD - 0.1f,
             DRV_EFFECT_STRIKE_MEDIUM,
             ANGULAR_VEL_HEAVY_THRESHOLD,
             DRV_EFFECT_STRIKE_HEAVY);

    init_octave_buttons();
    init_drv_i2c();
    g_drv_ready = probe_drv2605();
    ESP_LOGI(TAG, "After probe_drv2605(): g_drv_ready=%s", g_drv_ready ? "true" : "false");
    if (g_drv_ready) {
        if (trigger_drv2605_effect(DRV_EFFECT_STARTUP_PULSE) == DrvPulseResult::Ok) {
            ESP_LOGI(TAG, "DRV2605L startup pulse triggered");
        } else {
            log_drv_state("startup_pulse_failed");
        }
    } else {
        log_drv_state("probe_failed");
    }

    if (!init_bno_motion_pipeline()) {
        ESP_LOGE(TAG, "BNO085 motion pipeline init failed");
        while (true) {
            vTaskDelay(pdMS_TO_TICKS(1000));
        }
    }

    ESP_LOGI(TAG, "Motion pipeline ready. Waiting for terminal-confirmed bell hits to trigger haptic pulses.");

    while (true) {
        sh2_service();
        service_udp_commands();
        const uint64_t now_us = static_cast<uint64_t>(esp_timer_get_time());
        update_octave_buttons(now_us);
        maybe_log_motion(now_us);
        maybe_log_sensor_wait(now_us);
        vTaskDelay(pdMS_TO_TICKS(2));
    }
}

void relax_task_wdt_for_motion_test()
{
    const esp_task_wdt_config_t config = {
        .timeout_ms = 10000,
        .idle_core_mask = 0,
        .trigger_panic = false,
    };

    const esp_err_t err = esp_task_wdt_reconfigure(&config);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Reconfigured task watchdog for motion test (idle cores unsubscribed)");
    } else if (err != ESP_ERR_INVALID_STATE) {
        ESP_LOGW(TAG, "task watchdog reconfigure failed: %s", esp_err_to_name(err));
    }
}

void init_octave_buttons()
{
    const gpio_config_t config = {
        .pin_bit_mask =
            (1ULL << OCTAVE_BUTTON_GPIO_1) |
            (1ULL << OCTAVE_BUTTON_GPIO_2) |
            (1ULL << OCTAVE_BUTTON_GPIO_3) |
            (1ULL << OCTAVE_BUTTON_GPIO_4),
        .mode = GPIO_MODE_INPUT,
        .pull_up_en = GPIO_PULLUP_ENABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    ESP_ERROR_CHECK(gpio_config(&config));
    ESP_LOGI(
        TAG,
        "Octave buttons ready on GPIO%d-GPIO%d, default octave=%d",
        static_cast<int>(OCTAVE_BUTTON_GPIO_1),
        static_cast<int>(OCTAVE_BUTTON_GPIO_4),
        g_current_octave);
}

void update_octave_buttons(uint64_t now_us)
{
    if ((now_us - g_last_octave_scan_us) < OCTAVE_SCAN_INTERVAL_US) {
        return;
    }
    g_last_octave_scan_us = now_us;

    int next_octave = 0;
    if (gpio_get_level(OCTAVE_BUTTON_GPIO_1) == 0) {
        next_octave = 5;
    } else if (gpio_get_level(OCTAVE_BUTTON_GPIO_2) == 0) {
        next_octave = 4;
    } else if (gpio_get_level(OCTAVE_BUTTON_GPIO_3) == 0) {
        next_octave = 2;
    } else if (gpio_get_level(OCTAVE_BUTTON_GPIO_4) == 0) {
        next_octave = 1;
    }

    if (next_octave == 0 || next_octave == g_current_octave) {
      return;
    }
    if ((now_us - g_last_octave_change_us) < OCTAVE_DEBOUNCE_US) {
      return;
    }

    g_current_octave = next_octave;
    g_last_octave_change_us = now_us;
    ESP_LOGI(TAG, "Octave button selected octave=%d", g_current_octave);
}

// UDP发送JSON数据
esp_err_t udp_send_json(const char *json_str)
{
    if (g_udp_sock < 0) {
        return ESP_FAIL;
    }

    int len = strlen(json_str);
    int err = sendto(g_udp_sock, json_str, len, 0,
                     (struct sockaddr *)&g_dest_addr, sizeof(g_dest_addr));
    if (err < 0) {
        ESP_LOGW(TAG, "UDP send failed: errno %d", errno);
        return ESP_FAIL;
    }
    return ESP_OK;
}

// 发送光标位置
void send_cursor_position(float yaw, float pitch, float roll, uint64_t timestamp_us)
{
    char json[704];
    snprintf(json, sizeof(json),
             "{\"proto\":1,\"type\":\"cursor\",\"id\":%" PRId32 ",\"deviceId\":\"%s\","
             "\"yaw\":%.2f,\"pitch\":%.2f,\"roll\":%.2f,"
             "\"quaternion\":{\"w\":%.6f,\"x\":%.6f,\"y\":%.6f,\"z\":%.6f},"
             "\"angularVelocity\":%.2f,\"angularAcceleration\":%.2f,"
             "\"accelMagnitude\":%.3f,"
             "\"linearAcceleration\":{\"x\":%.3f,\"y\":%.3f,\"z\":%.3f},"
             "\"octave\":%d,\"timestamp\":%llu}",
             g_hammer_id,
             g_device_id,
             yaw,
             pitch,
             roll,
             g_motion.qw,
             g_motion.qx,
             g_motion.qy,
             g_motion.qz,
             g_motion.angular_vel,
             g_motion.angular_accel,
             g_motion.accel_mag,
             g_motion.ax,
             g_motion.ay,
             g_motion.az,
             g_current_octave,
             timestamp_us);
    udp_send_json(json);
}

// 发送击打事件
void send_strike_event(float force, StrikeTier tier, float yaw, float pitch, float roll, uint64_t timestamp_us)
{
    char json[832];
    snprintf(json, sizeof(json),
             "{\"proto\":1,\"type\":\"strike\",\"id\":%" PRId32 ",\"deviceId\":\"%s\","
             "\"force\":%.3f,\"tier\":\"%s\","
             "\"yaw\":%.2f,\"pitch\":%.2f,\"roll\":%.2f,"
             "\"quaternion\":{\"w\":%.6f,\"x\":%.6f,\"y\":%.6f,\"z\":%.6f},"
             "\"angularVelocity\":%.2f,\"angularAcceleration\":%.2f,"
             "\"accelMagnitude\":%.3f,"
             "\"linearAcceleration\":{\"x\":%.3f,\"y\":%.3f,\"z\":%.3f},"
             "\"octave\":%d,\"timestamp\":%llu}",
             g_hammer_id,
             g_device_id,
             force,
             strike_tier_name(tier),
             yaw,
             pitch,
             roll,
             g_motion.qw,
             g_motion.qx,
             g_motion.qy,
             g_motion.qz,
             g_motion.angular_vel,
             g_motion.angular_accel,
             g_motion.accel_mag,
             g_motion.ax,
             g_motion.ay,
             g_motion.az,
             g_current_octave,
             timestamp_us);
    udp_send_json(json);
}

// 初始化UDP socket
void init_udp()
{
    g_udp_sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_IP);
    if (g_udp_sock < 0) {
        ESP_LOGE(TAG, "Unable to create UDP socket: errno %d", errno);
        return;
    }

    // 设置广播
    int broadcast = 1;
    if (setsockopt(g_udp_sock, SOL_SOCKET, SO_BROADCAST, &broadcast, sizeof(broadcast)) < 0) {
        ESP_LOGE(TAG, "Failed to set SO_BROADCAST: errno %d", errno);
        close(g_udp_sock);
        g_udp_sock = -1;
        return;
    }

    int reuse = 1;
    if (setsockopt(g_udp_sock, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse)) < 0) {
        ESP_LOGW(TAG, "Failed to set SO_REUSEADDR: errno %d", errno);
    }

    struct sockaddr_in bind_addr = {};
    bind_addr.sin_family = AF_INET;
    bind_addr.sin_port = htons(UDP_PORT);
    bind_addr.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(g_udp_sock, reinterpret_cast<struct sockaddr *>(&bind_addr), sizeof(bind_addr)) < 0) {
        ESP_LOGE(TAG, "Failed to bind UDP socket on %d: errno %d", UDP_PORT, errno);
        close(g_udp_sock);
        g_udp_sock = -1;
        return;
    }

    // 配置目标地址（广播）
    memset(&g_dest_addr, 0, sizeof(g_dest_addr));
    g_dest_addr.sin_family = AF_INET;
    g_dest_addr.sin_port = htons(UDP_PORT);
    g_dest_addr.sin_addr.s_addr = inet_addr(UDP_BROADCAST_IP);

    ESP_LOGI(TAG, "UDP socket initialized, broadcasting to %s:%d", UDP_BROADCAST_IP, UDP_PORT);
    g_udp_start_us = static_cast<uint64_t>(esp_timer_get_time());
    g_first_cursor_log_us = 0;
}

void service_udp_commands()
{
    if (g_udp_sock < 0) {
        return;
    }

    std::array<char, 256> rx = {};
    while (true) {
        struct sockaddr_in source_addr = {};
        socklen_t source_addr_len = sizeof(source_addr);
        const int recv_len = recvfrom(
            g_udp_sock,
            rx.data(),
            rx.size() - 1,
            MSG_DONTWAIT,
            reinterpret_cast<struct sockaddr *>(&source_addr),
            &source_addr_len);
        if (recv_len < 0) {
            if (errno == EAGAIN || errno == EWOULDBLOCK) {
                return;
            }
            ESP_LOGW(TAG, "UDP recv failed: errno %d", errno);
            return;
        }
        if (recv_len == 0) {
            return;
        }

        rx[static_cast<size_t>(recv_len)] = '\0';
        handle_haptic_command_json(rx.data());
    }
}

void stop_udp()
{
    if (g_udp_sock >= 0) {
        close(g_udp_sock);
        g_udp_sock = -1;
    }
}

esp_err_t ensure_wifi_started()
{
    if (g_wifi_started) {
        return ESP_OK;
    }

    const esp_err_t err = esp_wifi_start();
    if (err == ESP_OK) {
        g_wifi_started = true;
    }
    return err;
}

const char *provision_stage_name(ProvisionUiStage stage)
{
    switch (stage) {
        case ProvisionUiStage::Ready:
            return "ready";
        case ProvisionUiStage::Applying:
            return "applying";
        case ProvisionUiStage::Connecting:
            return "connecting";
        case ProvisionUiStage::GettingIp:
            return "getting_ip";
        case ProvisionUiStage::Connected:
            return "connected";
        case ProvisionUiStage::Failed:
            return "failed";
    }
    return "ready";
}

int provision_stage_progress(ProvisionUiStage stage)
{
    switch (stage) {
        case ProvisionUiStage::Ready:
            return 0;
        case ProvisionUiStage::Applying:
            return 18;
        case ProvisionUiStage::Connecting:
            return std::min(72, 32 + g_wifi_retry_count * 4);
        case ProvisionUiStage::GettingIp:
            return 88;
        case ProvisionUiStage::Connected:
            return 100;
        case ProvisionUiStage::Failed:
            return 0;
    }
    return 0;
}

void set_provision_stage(ProvisionUiStage stage, const char *message)
{
    g_prov_stage = stage;
    snprintf(
        g_prov_status_message,
        sizeof(g_prov_status_message),
        "%s",
        message != nullptr ? message : "");
}

const char *wifi_disconnect_reason_message(uint8_t reason)
{
    switch (reason) {
        case WIFI_REASON_AUTH_EXPIRE:
        case WIFI_REASON_AUTH_FAIL:
        case WIFI_REASON_4WAY_HANDSHAKE_TIMEOUT:
        case WIFI_REASON_HANDSHAKE_TIMEOUT:
            return "密码错误或认证失败";
        case WIFI_REASON_NO_AP_FOUND:
#ifdef WIFI_REASON_NO_AP_FOUND_IN_RSSI_THRESHOLD
        case WIFI_REASON_NO_AP_FOUND_IN_RSSI_THRESHOLD:
#endif
#ifdef WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD
        case WIFI_REASON_NO_AP_FOUND_IN_AUTHMODE_THRESHOLD:
#endif
            return "未找到该WiFi";
        case WIFI_REASON_ASSOC_FAIL:
        case WIFI_REASON_CONNECTION_FAIL:
            return "路由器拒绝连接";
        default:
            return "连接失败，请重试";
    }
}

void append_json_string(std::string &out, const char *value)
{
    out.push_back('"');
    if (value != nullptr) {
        for (const char *cursor = value; *cursor != '\0'; ++cursor) {
            switch (*cursor) {
                case '\\':
                case '"':
                    out.push_back('\\');
                    out.push_back(*cursor);
                    break;
                case '\n':
                    out.append("\\n");
                    break;
                case '\r':
                    out.append("\\r");
                    break;
                case '\t':
                    out.append("\\t");
                    break;
                default:
                    out.push_back(*cursor);
                    break;
            }
        }
    }
    out.push_back('"');
}

std::string url_decode_form_value(const std::string &value)
{
    std::string decoded;
    decoded.reserve(value.size());

    for (size_t i = 0; i < value.size(); ++i) {
        const char ch = value[i];
        if (ch == '+') {
            decoded.push_back(' ');
            continue;
        }

        if (ch == '%' && i + 2 < value.size()) {
            const char hi = value[i + 1];
            const char lo = value[i + 2];
            if (std::isxdigit(static_cast<unsigned char>(hi)) &&
                std::isxdigit(static_cast<unsigned char>(lo))) {
                char byte[3] = {hi, lo, '\0'};
                decoded.push_back(static_cast<char>(strtol(byte, nullptr, 16)));
                i += 2;
                continue;
            }
        }

        decoded.push_back(ch);
    }

    return decoded;
}

bool parse_provision_form(const std::string &body, std::string &ssid, std::string &password)
{
    size_t cursor = 0;
    while (cursor < body.size()) {
        const size_t next = body.find('&', cursor);
        const std::string pair = body.substr(
            cursor,
            next == std::string::npos ? std::string::npos : next - cursor);
        const size_t equals = pair.find('=');
        if (equals != std::string::npos) {
            const std::string key = pair.substr(0, equals);
            const std::string value = url_decode_form_value(pair.substr(equals + 1));
            if (key == "ssid") {
                ssid = value;
            } else if (key == "password") {
                password = value;
            }
        }

        if (next == std::string::npos) {
            break;
        }
        cursor = next + 1;
    }

    return !ssid.empty();
}

struct DeferredProvisionContext {
    char ssid[sizeof(g_wifi_ssid)];
    char password[sizeof(g_wifi_pass)];
};

struct ProvisionTimeoutContext {
    uint32_t attempt_id;
};

void deferred_apply_wifi_credentials_task(void *arg)
{
    auto *ctx = static_cast<DeferredProvisionContext *>(arg);
    if (ctx == nullptr) {
        vTaskDelete(nullptr);
        return;
    }

    vTaskDelay(pdMS_TO_TICKS(250));
    if (!apply_wifi_credentials(ctx->ssid, ctx->password, "softap-web")) {
        set_provision_stage(ProvisionUiStage::Failed, "保存失败，请重试");
    }
    free(ctx);
    vTaskDelete(nullptr);
}

void provision_timeout_watchdog_task(void *arg)
{
    auto *ctx = static_cast<ProvisionTimeoutContext *>(arg);
    if (ctx == nullptr) {
        vTaskDelete(nullptr);
        return;
    }

    constexpr TickType_t kTimeout = pdMS_TO_TICKS(45000);
    constexpr TickType_t kSlice = pdMS_TO_TICKS(500);
    TickType_t waited = 0;

    while (waited < kTimeout) {
        if (ctx->attempt_id != g_prov_attempt_id ||
            g_prov_stage == ProvisionUiStage::Connected ||
            !g_should_connect_station) {
            free(ctx);
            vTaskDelete(nullptr);
            return;
        }
        vTaskDelay(kSlice);
        waited += kSlice;
    }

    if (ctx->attempt_id == g_prov_attempt_id &&
        g_prov_stage != ProvisionUiStage::Connected &&
        g_should_connect_station) {
        ESP_LOGE(TAG, "Provision timeout for attempt=%" PRIu32, ctx->attempt_id);
        g_should_connect_station = false;
        g_wifi_retry_count = 0;
        set_provisioned_flag(false);
        set_provision_stage(ProvisionUiStage::Failed, "连接超时，请重试");
        esp_wifi_disconnect();
        start_wifi_provisioning();
    }

    free(ctx);
    vTaskDelete(nullptr);
}

void start_provision_timeout_watchdog(uint32_t attempt_id)
{
    auto *ctx = static_cast<ProvisionTimeoutContext *>(calloc(1, sizeof(ProvisionTimeoutContext)));
    if (ctx == nullptr) {
        ESP_LOGW(TAG, "Failed to allocate provisioning timeout watchdog");
        return;
    }
    ctx->attempt_id = attempt_id;

    if (xTaskCreate(
            provision_timeout_watchdog_task,
            "prov_timeout",
            4096,
            ctx,
            4,
            nullptr) != pdPASS) {
        free(ctx);
        ESP_LOGW(TAG, "Failed to start provisioning timeout watchdog");
    }
}

bool apply_wifi_credentials(const char *ssid, const char *password, const char *source)
{
    if (ssid == nullptr || ssid[0] == '\0') {
        ESP_LOGE(TAG, "Reject empty SSID from %s", source);
        return false;
    }
    if (strlen(ssid) >= sizeof(g_wifi_ssid) || strlen(password) >= sizeof(g_wifi_pass)) {
        ESP_LOGE(TAG, "Reject oversize WiFi credentials from %s", source);
        return false;
    }

    if (!save_config_to_nvs(ssid, password, -1)) {
        ESP_LOGE(TAG, "Failed to persist WiFi credentials from %s", source);
        return false;
    }

    ESP_LOGI(TAG, "Applying WiFi credentials from %s, SSID=%s", source, ssid);
    ++g_prov_attempt_id;
    g_wifi_retry_count = 0;
    g_sta_connected = false;
    set_provision_stage(ProvisionUiStage::Applying, "已接收WiFi");
    stop_udp();
    start_wifi_station();
    start_provision_timeout_watchdog(g_prov_attempt_id);
    return true;
}

esp_err_t scan_wifi_networks_json(std::string &payload)
{
    wifi_scan_config_t scan_conf = {};
    esp_err_t err = esp_wifi_scan_start(&scan_conf, true);
    if (err != ESP_OK) {
        return err;
    }

    uint16_t ap_count = 0;
    ESP_ERROR_CHECK(esp_wifi_scan_get_ap_num(&ap_count));
    payload = "{\"networks\":[";

    if (ap_count > 0) {
        auto *ap_list = static_cast<wifi_ap_record_t *>(malloc(sizeof(wifi_ap_record_t) * ap_count));
        if (ap_list == nullptr) {
            return ESP_ERR_NO_MEM;
        }

        err = esp_wifi_scan_get_ap_records(&ap_count, ap_list);
        if (err != ESP_OK) {
            free(ap_list);
            return err;
        }

        std::string last_ssid;
        bool first_entry = true;
        for (uint16_t i = 0; i < ap_count; ++i) {
            const char *ssid = reinterpret_cast<const char *>(ap_list[i].ssid);
            if (ssid == nullptr || ssid[0] == '\0') {
                continue;
            }
            if (last_ssid == ssid) {
                continue;
            }
            if (!first_entry) {
                payload.push_back(',');
            }
            append_json_string(payload, ssid);
            last_ssid = ssid;
            first_entry = false;
        }

        free(ap_list);
    }

    payload.append("]}");
    return ESP_OK;
}

esp_err_t handle_http_root(httpd_req_t *req)
{
    constexpr size_t kPageBufferSize = 8192;
    char *page = static_cast<char *>(malloc(kPageBufferSize));
    if (page == nullptr) {
        httpd_resp_set_status(req, "500 Internal Server Error");
        return httpd_resp_sendstr(req, "memory alloc failed");
    }

    const int written = snprintf(
        page,
        kPageBufferSize,
        R"HTML(<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>%s</title>
  <style>
    body { font-family: sans-serif; margin: 0; background: #f4f6fb; color: #18202b; }
    main { max-width: 560px; margin: 0 auto; padding: 24px 18px 48px; }
    .card { background: #fff; border-radius: 18px; padding: 20px; box-shadow: 0 10px 28px rgba(20, 28, 45, 0.10); }
    h1 { font-size: 24px; margin: 0 0 8px; }
    label { display: block; margin: 14px 0 6px; font-weight: 600; }
    input, select, button { width: 100%%; box-sizing: border-box; border-radius: 12px; border: 1px solid #d7deea; font-size: 16px; padding: 12px 14px; }
    button { background: #1f6feb; color: #fff; border: 0; font-weight: 700; margin-top: 16px; }
    button.secondary { background: #edf2ff; color: #1f4db8; margin-top: 10px; }
    .row { display: flex; gap: 10px; }
    .row > * { flex: 1; }
    .meter { height: 12px; margin: 14px 0 10px; border-radius: 999px; background: #e7edf7; overflow: hidden; }
    .meter > div { height: 100%%; width: 0%%; background: linear-gradient(90deg, #1f6feb, #31b0ff); transition: width .25s ease; }
    .progress { display: flex; justify-content: space-between; gap: 12px; font-size: 14px; color: #344054; }
    .progress strong { font-size: 18px; color: #1f6feb; }
    #status { color: #344054; text-align: right; }
    .failed strong, .failed #status { color: #d92d20; }
    .connected strong, .connected #status { color: #067647; }
  </style>
</head>
<body>
  <main>
    <div class="card" id="card">
      <h1>%s</h1>
      <div class="meter"><div id="bar"></div></div>
      <div class="progress">
        <strong id="percent">0%%</strong>
        <div id="status">等待配网</div>
      </div>
      <label for="ssidSelect">附近 WiFi</label>
      <div class="row">
        <select id="ssidSelect"></select>
        <button class="secondary" type="button" onclick="scanWifi()">刷新</button>
      </div>
      <label for="ssid">WiFi 名称</label>
      <input id="ssid" value="%s" placeholder="请输入 2.4G WiFi 名称">
      <label for="password">WiFi 密码</label>
      <input id="password" type="password" placeholder="请输入 WiFi 密码">
      <button id="submitBtn" type="button" onclick="submitProvision()">开始配网</button>
    </div>
  </main>
  <script>
    let pollTimer = null;
    let submitPending = false;
    let fetchFailures = 0;
    let currentStage = 'ready';

    function setStatus(stage, progress, message) {
      const safeProgress = Math.max(0, Math.min(100, Number(progress || 0)));
      const card = document.getElementById('card');
      currentStage = stage || 'ready';
      document.getElementById('bar').style.width = `${safeProgress}%%`;
      document.getElementById('percent').textContent = `${safeProgress}%%`;
      document.getElementById('status').textContent = message || '等待配网';
      card.classList.toggle('failed', currentStage === 'failed');
      card.classList.toggle('connected', currentStage === 'connected');
      document.getElementById('submitBtn').disabled =
        currentStage === 'applying' || currentStage === 'connecting' || currentStage === 'getting_ip';
    }

    function renderStatus(data) {
      fetchFailures = 0;
      const stage = data.stage || 'ready';
      setStatus(stage, data.progress || 0, data.message || '等待配网');
      if (stage === 'connected' || stage === 'failed' || stage === 'ready') {
        submitPending = false;
      }
    }

    async function pollStatus() {
      try {
        const response = await fetch('/api/status', { cache: 'no-store' });
        const data = await response.json();
        renderStatus(data);
      } catch (error) {
        fetchFailures += 1;
        if (submitPending && fetchFailures >= 3 && currentStage !== 'connected') {
          submitPending = false;
          setStatus('failed', 0, '页面连接中断，请重新打开配网页面');
        }
      }
    }

    async function scanWifi() {
      if (!submitPending && currentStage === 'ready') {
        setStatus('ready', 0, '正在扫描附近 WiFi...');
      }
      try {
        const response = await fetch('/api/scan');
        const data = await response.json();
        const select = document.getElementById('ssidSelect');
        select.innerHTML = '';
        for (const name of data.networks || []) {
          const option = document.createElement('option');
          option.value = name;
          option.textContent = name;
          select.appendChild(option);
        }
        if (select.options.length > 0) {
          document.getElementById('ssid').value = select.value;
        }
        if (!submitPending && currentStage === 'ready') {
          setStatus('ready', 0, select.options.length > 0 ? '请选择 WiFi' : '未扫描到附近 WiFi');
        }
      } catch (error) {
        if (!submitPending && currentStage === 'ready') {
          setStatus('ready', 0, '扫描失败，请稍后重试');
        }
      }
    }

    document.getElementById('ssidSelect').addEventListener('change', (event) => {
      document.getElementById('ssid').value = event.target.value;
    });

    async function submitProvision() {
      const ssid = document.getElementById('ssid').value.trim();
      const password = document.getElementById('password').value;
      if (!ssid) {
        setStatus('failed', 0, 'WiFi 名称不能为空');
        return;
      }
      submitPending = true;
      setStatus('applying', 12, '正在提交 WiFi...');
      const body = new URLSearchParams({ ssid, password });
      let response;
      try {
        response = await fetch('/api/provision', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
          body,
        });
      } catch (error) {
        submitPending = false;
        setStatus('failed', 0, '提交失败，请重试');
        return;
      }
      const text = await response.text();
      if (!response.ok) {
        submitPending = false;
        setStatus('failed', 0, text);
        return;
      }
      setStatus('applying', 18, '已接收 WiFi');
      await pollStatus();
    }

    pollStatus();
    scanWifi();
    pollTimer = setInterval(pollStatus, 1000);
  </script>
</body>
</html>)HTML",
        g_prov_service_name,
        g_prov_service_name,
        g_wifi_provisioned ? g_wifi_ssid : "");
    if (written < 0 || static_cast<size_t>(written) >= kPageBufferSize) {
        free(page);
        httpd_resp_set_status(req, "500 Internal Server Error");
        return httpd_resp_sendstr(req, "page render overflow");
    }

    httpd_resp_set_type(req, "text/html; charset=utf-8");
    const esp_err_t send_err = httpd_resp_sendstr(req, page);
    free(page);
    return send_err;
}

esp_err_t handle_http_scan(httpd_req_t *req)
{
    std::string payload;
    const esp_err_t err = scan_wifi_networks_json(payload);
    if (err != ESP_OK) {
        httpd_resp_set_status(req, "500 Internal Server Error");
        return httpd_resp_sendstr(req, "{\"error\":\"scan_failed\"}");
    }

    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, payload.c_str(), payload.size());
}

esp_err_t handle_http_status(httpd_req_t *req)
{
    std::string payload = "{\"device\":";
    append_json_string(payload, g_prov_service_name);
    payload.append(",\"stage\":");
    append_json_string(payload, provision_stage_name(g_prov_stage));
    payload.append(",\"progress\":");
    payload.append(std::to_string(provision_stage_progress(g_prov_stage)));
    payload.append(",\"message\":");
    append_json_string(payload, g_prov_status_message);
    payload.append(",\"provisioned\":");
    payload.append(g_wifi_provisioned ? "true" : "false");
    payload.append(",\"connected\":");
    payload.append(g_sta_connected ? "true" : "false");
    payload.append(",\"currentSsid\":");
    append_json_string(payload, (g_wifi_provisioned || g_should_connect_station) ? g_wifi_ssid : "");
    payload.append(",\"retry\":");
    payload.append(std::to_string(g_wifi_retry_count));
    payload.append(",\"maxRetry\":");
    payload.append(std::to_string(WIFI_MAX_RETRY));
    payload.append("}");

    httpd_resp_set_type(req, "application/json");
    return httpd_resp_send(req, payload.c_str(), payload.size());
}

esp_err_t handle_http_provision(httpd_req_t *req)
{
    if (req->content_len <= 0 || req->content_len > 512) {
        httpd_resp_set_status(req, "400 Bad Request");
        return httpd_resp_sendstr(req, "请求内容无效");
    }

    std::string body;
    body.resize(req->content_len);
    int received = 0;
    while (received < req->content_len) {
        const int ret = httpd_req_recv(
            req,
            body.data() + received,
            req->content_len - received);
        if (ret <= 0) {
            httpd_resp_set_status(req, "400 Bad Request");
            return httpd_resp_sendstr(req, "读取请求失败");
        }
        received += ret;
    }

    std::string ssid;
    std::string password;
    if (!parse_provision_form(body, ssid, password)) {
        httpd_resp_set_status(req, "400 Bad Request");
        return httpd_resp_sendstr(req, "SSID 不能为空");
    }

    auto *ctx = static_cast<DeferredProvisionContext *>(calloc(1, sizeof(DeferredProvisionContext)));
    if (ctx == nullptr) {
        httpd_resp_set_status(req, "500 Internal Server Error");
        return httpd_resp_sendstr(req, "内存不足，无法启动配网");
    }
    strlcpy(ctx->ssid, ssid.c_str(), sizeof(ctx->ssid));
    strlcpy(ctx->password, password.c_str(), sizeof(ctx->password));
    set_provision_stage(ProvisionUiStage::Applying, "已接收 WiFi");

    if (xTaskCreate(
            deferred_apply_wifi_credentials_task,
            "prov_apply",
            6144,
            ctx,
            5,
            nullptr) != pdPASS) {
        free(ctx);
        httpd_resp_set_status(req, "500 Internal Server Error");
        return httpd_resp_sendstr(req, "启动配网任务失败");
    }

    return httpd_resp_sendstr(req, "ok");
}

esp_err_t handle_http_captive_redirect(httpd_req_t *req)
{
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    return handle_http_root(req);
}

esp_err_t handle_http_404_redirect(httpd_req_t *req, httpd_err_code_t err)
{
    (void)err;
    httpd_resp_set_status(req, "303 See Other");
    httpd_resp_set_hdr(req, "Cache-Control", "no-store");
    httpd_resp_set_hdr(req, "Location", "/");
    return httpd_resp_sendstr(req, "Redirect to captive portal");
}

void start_http_provision_server()
{
    if (g_prov_http_server != nullptr) {
        return;
    }

    httpd_config_t config = HTTPD_DEFAULT_CONFIG();
    config.max_uri_handlers = 16;
    config.max_open_sockets = 7;
    config.stack_size = 8192;
    config.lru_purge_enable = true;
    config.uri_match_fn = httpd_uri_match_wildcard;

    ESP_ERROR_CHECK(httpd_start(&g_prov_http_server, &config));

    const httpd_uri_t root = {
        .uri = "/",
        .method = HTTP_GET,
        .handler = handle_http_root,
        .user_ctx = nullptr,
    };
    const httpd_uri_t scan = {
        .uri = "/api/scan",
        .method = HTTP_GET,
        .handler = handle_http_scan,
        .user_ctx = nullptr,
    };
    const httpd_uri_t status = {
        .uri = "/api/status",
        .method = HTTP_GET,
        .handler = handle_http_status,
        .user_ctx = nullptr,
    };
    const httpd_uri_t provision = {
        .uri = "/api/provision",
        .method = HTTP_POST,
        .handler = handle_http_provision,
        .user_ctx = nullptr,
    };
    const httpd_uri_t captive_android = {
        .uri = "/generate_204",
        .method = HTTP_GET,
        .handler = handle_http_captive_redirect,
        .user_ctx = nullptr,
    };
    const httpd_uri_t captive_android_alt = {
        .uri = "/gen_204",
        .method = HTTP_GET,
        .handler = handle_http_captive_redirect,
        .user_ctx = nullptr,
    };
    const httpd_uri_t captive_ios = {
        .uri = "/hotspot-detect.html",
        .method = HTTP_GET,
        .handler = handle_http_captive_redirect,
        .user_ctx = nullptr,
    };
    const httpd_uri_t captive_windows = {
        .uri = "/connecttest.txt",
        .method = HTTP_GET,
        .handler = handle_http_captive_redirect,
        .user_ctx = nullptr,
    };
    const httpd_uri_t captive_windows_ncsi = {
        .uri = "/ncsi.txt",
        .method = HTTP_GET,
        .handler = handle_http_captive_redirect,
        .user_ctx = nullptr,
    };
    const httpd_uri_t captive_success = {
        .uri = "/library/test/success.html",
        .method = HTTP_GET,
        .handler = handle_http_captive_redirect,
        .user_ctx = nullptr,
    };
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &root));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &scan));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &status));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &provision));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &captive_android));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &captive_android_alt));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &captive_ios));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &captive_windows));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &captive_windows_ncsi));
    ESP_ERROR_CHECK(httpd_register_uri_handler(g_prov_http_server, &captive_success));
    ESP_ERROR_CHECK(httpd_register_err_handler(
        g_prov_http_server,
        HTTPD_404_NOT_FOUND,
        handle_http_404_redirect));
}

void stop_http_provision_server()
{
    if (g_prov_http_server == nullptr) {
        return;
    }

    httpd_stop(g_prov_http_server);
    g_prov_http_server = nullptr;
}

int build_captive_dns_response(const uint8_t *request,
                               int request_len,
                               uint8_t *response,
                               int response_size)
{
    if (request == nullptr || response == nullptr || request_len < 12 || response_size < 32) {
        return 0;
    }

    int question_end = 12;
    while (question_end < request_len && request[question_end] != 0) {
        question_end += request[question_end] + 1;
    }
    if (question_end + 5 > request_len) {
        return 0;
    }
    question_end += 5;  // zero label + qtype + qclass

    if (question_end + 16 > response_size) {
        return 0;
    }

    memcpy(response, request, question_end);
    response[2] = 0x81;
    response[3] = 0x80;
    response[6] = 0x00;
    response[7] = 0x01;
    response[8] = 0x00;
    response[9] = 0x00;
    response[10] = 0x00;
    response[11] = 0x00;

    int offset = question_end;
    response[offset++] = 0xC0;
    response[offset++] = 0x0C;
    response[offset++] = 0x00;
    response[offset++] = 0x01;
    response[offset++] = 0x00;
    response[offset++] = 0x01;
    response[offset++] = 0x00;
    response[offset++] = 0x00;
    response[offset++] = 0x00;
    response[offset++] = 0x3C;
    response[offset++] = 0x00;
    response[offset++] = 0x04;

    const uint32_t captive_ip = inet_addr(PROV_AP_IP);
    memcpy(response + offset, &captive_ip, sizeof(captive_ip));
    offset += sizeof(captive_ip);

    return offset;
}

void dns_captive_portal_task(void *arg)
{
    (void)arg;

    int sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (sock < 0) {
        ESP_LOGE(TAG, "Failed to create captive DNS socket: errno=%d", errno);
        g_dns_captive_task = nullptr;
        vTaskDelete(nullptr);
        return;
    }

    struct sockaddr_in addr = {};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(53);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);

    if (bind(sock, reinterpret_cast<struct sockaddr *>(&addr), sizeof(addr)) < 0) {
        ESP_LOGE(TAG, "Failed to bind captive DNS socket: errno=%d", errno);
        close(sock);
        g_dns_captive_task = nullptr;
        vTaskDelete(nullptr);
        return;
    }

    g_dns_captive_sock = sock;
    ESP_LOGI(TAG, "Captive DNS server started on %s:53", PROV_AP_IP);

    while (true) {
        uint8_t request[512];
        uint8_t response[512];
        struct sockaddr_in client_addr = {};
        socklen_t client_len = sizeof(client_addr);
        const int recv_len = recvfrom(
            sock,
            request,
            sizeof(request),
            0,
            reinterpret_cast<struct sockaddr *>(&client_addr),
            &client_len);
        if (recv_len <= 0) {
            break;
        }

        const int resp_len = build_captive_dns_response(
            request,
            recv_len,
            response,
            sizeof(response));
        if (resp_len > 0) {
            sendto(
                sock,
                response,
                resp_len,
                0,
                reinterpret_cast<struct sockaddr *>(&client_addr),
                client_len);
        }
    }

    if (g_dns_captive_sock >= 0) {
        close(g_dns_captive_sock);
        g_dns_captive_sock = -1;
    }
    g_dns_captive_task = nullptr;
    ESP_LOGI(TAG, "Captive DNS server stopped");
    vTaskDelete(nullptr);
}

void start_dns_captive_portal()
{
    if (g_dns_captive_task != nullptr) {
        return;
    }

    xTaskCreate(
        dns_captive_portal_task,
        "captive_dns",
        4096,
        nullptr,
        4,
        &g_dns_captive_task);
}

void stop_dns_captive_portal()
{
    if (g_dns_captive_sock >= 0) {
        shutdown(g_dns_captive_sock, SHUT_RDWR);
        close(g_dns_captive_sock);
        g_dns_captive_sock = -1;
    }
}

void configure_softap_netif()
{
    if (g_ap_netif == nullptr) {
        ESP_LOGW(TAG, "AP netif is null, skip SoftAP netif config");
        return;
    }

    esp_err_t err = esp_netif_dhcps_stop(g_ap_netif);
    if (err != ESP_OK && err != ESP_ERR_ESP_NETIF_DHCP_ALREADY_STOPPED) {
        ESP_LOGW(TAG, "Failed to stop SoftAP DHCP server: %s", esp_err_to_name(err));
    }

    esp_netif_ip_info_t ip_info = {};
    ESP_ERROR_CHECK(esp_netif_str_to_ip4(PROV_AP_IP, &ip_info.ip));
    ESP_ERROR_CHECK(esp_netif_str_to_ip4(PROV_AP_IP, &ip_info.gw));
    ESP_ERROR_CHECK(esp_netif_str_to_ip4(PROV_AP_NETMASK, &ip_info.netmask));
    ESP_ERROR_CHECK(esp_netif_set_ip_info(g_ap_netif, &ip_info));

    err = esp_netif_dhcps_start(g_ap_netif);
    if (err != ESP_OK && err != ESP_ERR_ESP_NETIF_DHCP_ALREADY_STARTED) {
        ESP_LOGE(TAG, "Failed to start SoftAP DHCP server: %s", esp_err_to_name(err));
        ESP_ERROR_CHECK(err);
    }

    ESP_LOGI(TAG, "SoftAP netif configured: ip=%s netmask=%s",
             PROV_AP_IP,
             PROV_AP_NETMASK);
}

void refresh_prov_service_name()
{
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    // 用 MAC 后 4 位作为 service name 后缀，避免 deviceId 末尾 "-H<id>" 被错算进去
    snprintf(g_prov_service_name,
             sizeof(g_prov_service_name),
             "BianzongHammer-%02X%02X",
             mac[4], mac[5]);
}

int32_t generate_random_hammer_id()
{
    return static_cast<int32_t>((esp_random() % 12) + 1);
}

void refresh_device_identity()
{
    uint8_t mac[6] = {0};
    ESP_ERROR_CHECK(esp_read_mac(mac, ESP_MAC_WIFI_STA));
    // 末尾追加 "-H<id>"（≤10 hex + 3 后缀 = 15 字节），保证同一子网多击锤 deviceId 唯一
    snprintf(g_device_id,
             sizeof(g_device_id),
             "%02X%02X%02X%02X%02X%02X-H%" PRId32,
             mac[0],
             mac[1],
             mac[2],
             mac[3],
             mac[4],
             mac[5],
             g_hammer_id);
    refresh_prov_service_name();
}

void wifi_event_handler(void *arg, esp_event_base_t event_base,
                        int32_t event_id, void *event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        if (g_should_connect_station) {
            esp_wifi_connect();
        }
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STACONNECTED) {
        auto *event = static_cast<wifi_event_ap_staconnected_t *>(event_data);
        if (event != nullptr) {
            ESP_LOGI(
                TAG,
                "Phone joined SoftAP: " MACSTR ", aid=%d",
                MAC2STR(event->mac),
                event->aid);
        }
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_AP_STADISCONNECTED) {
        auto *event = static_cast<wifi_event_ap_stadisconnected_t *>(event_data);
        if (event != nullptr) {
            ESP_LOGW(
                TAG,
                "Phone left SoftAP: " MACSTR ", aid=%d, reason=%u",
                MAC2STR(event->mac),
                event->aid,
                static_cast<unsigned>(event->reason));
        }
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        auto *event = static_cast<wifi_event_sta_disconnected_t *>(event_data);
        const uint8_t reason = event != nullptr ? event->reason : 0;
        g_sta_connected = false;
        stop_udp();
        if (!g_should_connect_station) {
            ESP_LOGI(TAG, "Ignore STA disconnect while provisioning AP is active");
            return;
        }
        if (g_should_connect_station && g_wifi_retry_count < WIFI_MAX_RETRY) {
            esp_wifi_connect();
            g_wifi_retry_count++;
            ESP_LOGI(
                TAG,
                "Retry connecting to WiFi... (%d/%d), reason=%u",
                g_wifi_retry_count,
                WIFI_MAX_RETRY,
                static_cast<unsigned>(reason));
            char message[96];
            snprintf(
                message,
                sizeof(message),
                "正在连接路由器（%d/%d）",
                g_wifi_retry_count,
                WIFI_MAX_RETRY);
            set_provision_stage(ProvisionUiStage::Connecting, message);
        } else {
            ESP_LOGE(
                TAG,
                "Failed to connect to WiFi after %d retries, reason=%u",
                WIFI_MAX_RETRY,
                static_cast<unsigned>(reason));
            g_should_connect_station = false;
            g_wifi_retry_count = 0;
            set_provisioned_flag(false);
            if (!g_softap_active) {
                start_wifi_provisioning();
            }
            set_provision_stage(ProvisionUiStage::Failed, wifi_disconnect_reason_message(reason));
        }
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_CONNECTED) {
        set_provision_stage(ProvisionUiStage::GettingIp, "已连接路由器，正在获取IP");
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_AP_STAIPASSIGNED) {
        ip_event_ap_staipassigned_t *event = (ip_event_ap_staipassigned_t *)event_data;
        if (event != nullptr) {
            ESP_LOGI(TAG, "SoftAP assigned DHCP lease: " IPSTR, IP2STR(&event->ip));
        }
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t *event = (ip_event_got_ip_t *)event_data;
        ESP_LOGI(TAG, "Got IP address: " IPSTR, IP2STR(&event->ip_info.ip));
        g_wifi_retry_count = 0;
        g_sta_connected = true;
        g_wifi_provisioned = true;
        set_provisioned_flag(true);
        set_provision_stage(ProvisionUiStage::Connected, "配网成功");
        if (g_softap_active) {
            xTaskCreate(
                [](void *arg) {
                    (void)arg;
                    vTaskDelay(pdMS_TO_TICKS(1500));
                    stop_softap_provisioning();
                    vTaskDelete(nullptr);
                },
                "stop_softap",
                4096,
                nullptr,
                4,
                nullptr);
        }

        // WiFi连接成功，初始化UDP
        vTaskDelay(pdMS_TO_TICKS(500));
        init_udp();
    }
}

// 从NVS加载配置
void load_config_from_nvs()
{
    nvs_handle_t nvs_handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READONLY, &nvs_handle);

    if (err == ESP_OK) {
        size_t ssid_len = sizeof(g_wifi_ssid);
        size_t pass_len = sizeof(g_wifi_pass);
        uint8_t provisioned = 0;

        err = nvs_get_u8(nvs_handle, NVS_KEY_PROVISIONED, &provisioned);
        g_wifi_provisioned = (err == ESP_OK && provisioned == 1);

        // 读取WiFi SSID
        err = nvs_get_str(nvs_handle, NVS_KEY_SSID, g_wifi_ssid, &ssid_len);
        if (err != ESP_OK) {
            strcpy(g_wifi_ssid, DEFAULT_WIFI_SSID);
            ESP_LOGI(TAG, "Using default SSID: %s", g_wifi_ssid);
        } else {
            ESP_LOGI(TAG, "Loaded SSID from NVS: %s", g_wifi_ssid);
        }

        // 读取WiFi密码
        err = nvs_get_str(nvs_handle, NVS_KEY_PASS, g_wifi_pass, &pass_len);
        if (err != ESP_OK) {
            strcpy(g_wifi_pass, DEFAULT_WIFI_PASS);
            ESP_LOGI(TAG, "Using default password");
        } else {
            ESP_LOGI(TAG, "Loaded password from NVS");
        }

        // 读取击锤ID
        err = nvs_get_i32(nvs_handle, NVS_KEY_ID, &g_hammer_id);
        if (err != ESP_OK || g_hammer_id < 1 || g_hammer_id > 12) {
            g_hammer_id = generate_random_hammer_id();
            ESP_LOGI(TAG, "Generated random Hammer ID: %d", g_hammer_id);
            if (!save_config_to_nvs(nullptr, nullptr, g_hammer_id)) {
                ESP_LOGW(TAG, "Failed to persist generated Hammer ID");
            }
        } else {
            ESP_LOGI(TAG, "Loaded Hammer ID from NVS: %d", g_hammer_id);
        }

        ESP_LOGI(TAG, "WiFi provisioned flag: %s", g_wifi_provisioned ? "true" : "false");

        nvs_close(nvs_handle);
        refresh_device_identity();
    } else {
        // NVS未初始化或首次启动，使用默认值
        strcpy(g_wifi_ssid, DEFAULT_WIFI_SSID);
        strcpy(g_wifi_pass, DEFAULT_WIFI_PASS);
        g_hammer_id = generate_random_hammer_id();
        g_wifi_provisioned = false;
        ESP_LOGI(TAG, "NVS not available, generated Hammer ID: %d", g_hammer_id);
        if (!save_config_to_nvs(nullptr, nullptr, g_hammer_id)) {
            ESP_LOGW(TAG, "Failed to persist initial random Hammer ID");
        }
        refresh_device_identity();
    }
}

// 保存配置到NVS
bool save_config_to_nvs(const char *ssid, const char *pass, int hammer_id)
{
    nvs_handle_t nvs_handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs_handle);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS: %s", esp_err_to_name(err));
        return false;
    }

    // 保存WiFi SSID
    if (ssid != nullptr) {
        err = nvs_set_str(nvs_handle, NVS_KEY_SSID, ssid);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "Failed to save SSID: %s", esp_err_to_name(err));
            nvs_close(nvs_handle);
            return false;
        }
        strcpy(g_wifi_ssid, ssid);
        ESP_LOGI(TAG, "Saved SSID to NVS: %s", ssid);
    }

    // 保存WiFi密码
    if (pass != nullptr) {
        err = nvs_set_str(nvs_handle, NVS_KEY_PASS, pass);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "Failed to save password: %s", esp_err_to_name(err));
            nvs_close(nvs_handle);
            return false;
        }
        strcpy(g_wifi_pass, pass);
        ESP_LOGI(TAG, "Saved password to NVS");
    }

    // 保存击锤ID
    if (hammer_id >= 1 && hammer_id <= 12) {
        err = nvs_set_i32(nvs_handle, NVS_KEY_ID, hammer_id);
        if (err != ESP_OK) {
            ESP_LOGE(TAG, "Failed to save Hammer ID: %s", esp_err_to_name(err));
            nvs_close(nvs_handle);
            return false;
        }
        const int32_t prev = g_hammer_id;
        g_hammer_id = hammer_id;
        if (prev != g_hammer_id) {
            refresh_device_identity();
        }
        ESP_LOGI(TAG, "Saved Hammer ID to NVS: %d", hammer_id);
    }

    // 提交更改
    err = nvs_commit(nvs_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to commit NVS: %s", esp_err_to_name(err));
        nvs_close(nvs_handle);
        return false;
    }

    nvs_close(nvs_handle);
    ESP_LOGI(TAG, "Configuration saved successfully");
    return true;
}

bool set_provisioned_flag(bool provisioned)
{
    nvs_handle_t nvs_handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &nvs_handle);
    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to open NVS for provisioned flag: %s", esp_err_to_name(err));
        return false;
    }

    err = nvs_set_u8(nvs_handle, NVS_KEY_PROVISIONED, provisioned ? 1 : 0);
    if (err == ESP_OK) {
        err = nvs_commit(nvs_handle);
    }
    nvs_close(nvs_handle);

    if (err != ESP_OK) {
        ESP_LOGE(TAG, "Failed to save provisioned flag: %s", esp_err_to_name(err));
        return false;
    }

    g_wifi_provisioned = provisioned;
    return true;
}

void start_wifi_station()
{
    const bool was_wifi_started = g_wifi_started;
    wifi_config_t wifi_config = {};
    strcpy(reinterpret_cast<char *>(wifi_config.sta.ssid), g_wifi_ssid);
    strcpy(reinterpret_cast<char *>(wifi_config.sta.password), g_wifi_pass);

    g_wifi_retry_count = 1;
    g_should_connect_station = true;
    set_provision_stage(ProvisionUiStage::Connecting, "正在连接路由器（1/10）");

    ESP_ERROR_CHECK(esp_wifi_set_mode(g_softap_active ? WIFI_MODE_APSTA : WIFI_MODE_STA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config));
    const esp_err_t start_err = ensure_wifi_started();
    if (start_err != ESP_OK) {
        ESP_ERROR_CHECK(start_err);
    }
    if (was_wifi_started) {
        const esp_err_t disconnect_err = esp_wifi_disconnect();
        if (disconnect_err != ESP_OK &&
            disconnect_err != ESP_ERR_WIFI_NOT_CONNECT &&
            disconnect_err != ESP_ERR_WIFI_CONN) {
            ESP_LOGW(TAG, "esp_wifi_disconnect returned %s", esp_err_to_name(disconnect_err));
        }

        const esp_err_t connect_err = esp_wifi_connect();
        if (connect_err != ESP_OK && connect_err != ESP_ERR_WIFI_CONN) {
            ESP_ERROR_CHECK(connect_err);
        }
        if (connect_err == ESP_ERR_WIFI_CONN) {
            ESP_LOGI(TAG, "WiFi STA connect already in progress");
        }
    } else {
        ESP_LOGI(TAG, "WiFi STA start requested, waiting for STA_START event");
    }
    ESP_LOGI(TAG, "WiFi STA started. Hammer ID=%" PRId32 ", target SSID=%s",
             g_hammer_id, g_wifi_ssid);
}

void start_softap_provisioning()
{
    if (g_softap_active) {
        configure_softap_netif();
        start_http_provision_server();
        start_dns_captive_portal();
        ESP_LOGI(TAG, "SoftAP provisioning already active: ssid=%s", g_prov_service_name);
        return;
    }

    wifi_config_t ap_config = {};
    ap_config.ap.max_connection = PROV_AP_MAX_CONN;
    memcpy(
        ap_config.ap.ssid,
        g_prov_service_name,
        std::min(strlen(g_prov_service_name), sizeof(ap_config.ap.ssid)));
    ap_config.ap.ssid_len = strlen(g_prov_service_name);
    ap_config.ap.channel = 1;
    if (strlen(PROV_AP_PASS) == 0) {
        memset(ap_config.ap.password, 0, sizeof(ap_config.ap.password));
        ap_config.ap.authmode = WIFI_AUTH_OPEN;
    } else {
        strlcpy(
            reinterpret_cast<char *>(ap_config.ap.password),
            PROV_AP_PASS,
            sizeof(ap_config.ap.password));
        ap_config.ap.authmode = WIFI_AUTH_WPA_WPA2_PSK;
    }

    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_APSTA));
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &ap_config));
    const esp_err_t start_err = ensure_wifi_started();
    if (start_err != ESP_OK && start_err != ESP_ERR_WIFI_CONN) {
        ESP_ERROR_CHECK(start_err);
    }

    configure_softap_netif();
    g_softap_active = true;
    start_http_provision_server();
    start_dns_captive_portal();
    if (g_prov_stage != ProvisionUiStage::Failed) {
        set_provision_stage(ProvisionUiStage::Ready, "请选择 WiFi");
    }
    ESP_LOGI(
        TAG,
        "SoftAP provisioning started: ssid=%s portal=http://%s",
        g_prov_service_name,
        PROV_AP_IP);
}

void stop_softap_provisioning()
{
    stop_dns_captive_portal();
    stop_http_provision_server();
    if (!g_softap_active) {
        return;
    }

    g_softap_active = false;
    if (g_wifi_started) {
        const wifi_mode_t next_mode = g_should_connect_station ? WIFI_MODE_STA : WIFI_MODE_NULL;
        ESP_ERROR_CHECK(esp_wifi_set_mode(next_mode));
    }
    ESP_LOGI(TAG, "SoftAP provisioning stopped");
}

void start_wifi_provisioning()
{
    g_should_connect_station = false;
    g_wifi_retry_count = 0;
    start_softap_provisioning();
    if (g_prov_stage != ProvisionUiStage::Failed) {
        set_provision_stage(ProvisionUiStage::Ready, "请选择 WiFi");
    }
    ESP_LOGI(
        TAG,
        "Provisioning ready in SoftAP mode (%s).",
        g_prov_service_name);
}

void init_wifi_provisioning()
{
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);

    // 从NVS加载配置
    load_config_from_nvs();
    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    g_sta_netif = esp_netif_create_default_wifi_sta();
    g_ap_netif = esp_netif_create_default_wifi_ap();
    refresh_device_identity();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    ESP_ERROR_CHECK(esp_event_handler_register(WIFI_EVENT,
                                               ESP_EVENT_ANY_ID,
                                               &wifi_event_handler,
                                               nullptr));
    ESP_ERROR_CHECK(esp_event_handler_register(IP_EVENT,
                                               IP_EVENT_STA_GOT_IP,
                                               &wifi_event_handler,
                                               nullptr));

    if (g_wifi_provisioned) {
        ESP_LOGI(TAG, "Stored WiFi credentials found, start STA mode");
        start_wifi_station();
    } else {
        ESP_LOGI(TAG, "No WiFi credentials found, start SoftAP provisioning");
        start_wifi_provisioning();
    }

    ESP_LOGI(TAG, "Provisioning service ready. Hammer ID=%" PRId32 ", service=%s",
             g_hammer_id, g_prov_service_name);
}

}  // namespace

extern "C" void app_main(void)
{
    relax_task_wdt_for_motion_test();

    // 初始化WiFi热点配网
    ESP_LOGI(TAG, "Initializing WiFi provisioning...");
    init_wifi_provisioning();

    BaseType_t rc = xTaskCreatePinnedToCore(
        motion_task,
        "motion_task",
        MOTION_TASK_STACK_WORDS,
        nullptr,
        MOTION_TASK_PRIORITY,
        nullptr,
        MOTION_TASK_CORE);
    ESP_ERROR_CHECK(rc == pdPASS ? ESP_OK : ESP_FAIL);
}
