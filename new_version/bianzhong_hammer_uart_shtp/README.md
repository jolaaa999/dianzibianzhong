# ESP32-S3 编钟击锤固件

当前正式固件以 [src/main.cpp](/home/abc/桌面/bianz1.0/321shuzibianz/firmware/bianzhong_hammer/src/main.cpp:1) 为准，职责包括：
- `BNO085 UART-SHTP` 姿态读取
- `DRV2605L I2C` 触觉反馈
- `ESP32 BluFi + SoftAP 网页` 双模式配网
- 向 Flutter 广播 `UDP 3333` 的 `cursor/strike` 消息

当前版本保留 `NVS`，并支持 `BluFi` 与 `击锤 SoftAP + 网页` 双模式并存。USB 只用于 `烧录` 和 `日志诊断`。

## 硬件连接

### BNO085

```text
BNO085 TX  -> ESP32-S3 GPIO1
BNO085 RX  -> ESP32-S3 GPIO2
BNO085 VCC -> 3.3V
BNO085 GND -> GND
BNO085 PS0 -> 3.3V
BNO085 PS1 -> GND
```

说明：
- 必须工作在 `UART-SHTP`
- 当前 UART 参数：`3000000 8N1`

### DRV2605L

```text
ESP32-S3 GPIO20 -> DRV2605L SDA
ESP32-S3 GPIO19 -> DRV2605L SCL
3.3V            -> VCC
GND             -> GND
OUT+ / OUT-     -> LRA
```

## 编译与烧录

```bash
cd firmware/bianzhong_hammer
./build.sh
./build.sh --upload -p /dev/ttyACM0
```

查看日志：

```bash
./build.sh --monitor -p /dev/ttyACM0
```

如果端口是 `/dev/ttyUSB0`，把参数换成对应端口。

## 配网方式

上电后，如果设备未配网、或已保存 WiFi 但重连失败，会同时开放：
- `BluFi` 设备名前缀：`BianzongHammer-`
- `WiFi AP` 名称：`BianzongHammer-XXXXXX`
- `WiFi AP` 密码：`12345678`
- `网页地址`：`http://192.168.4.1`
- `ESP32` 负责扫描附近 WiFi，并把列表回传给 App 或网页

推荐流程：
1. 在手机 App 中打开 `蓝牙配网`
2. 选择对应的 `BianzongHammer-XXXXXX`
3. 输入目标 WiFi 的 `SSID / Password`
4. 提交后，击锤会自动连接目标 WiFi
5. 连接成功后自动关闭热点和网页
6. 开始广播 `UDP 3333`

网页兜底流程：
1. 手机或其他设备连接击锤热点 `BianzongHammer-XXXXXX`
2. 输入密码 `12345678`
3. 打开 `http://192.168.4.1`
4. 扫描并选择目标 WiFi
5. 提交 `SSID / Password`
6. 等待击锤连网，联网成功后热点自动关闭

补充：
- `Hammer ID` 由设备随机生成 `1..12`
- 目标 `WiFi SSID/Password`、`Hammer ID`、`provisioned flag` 都保存在 `NVS`
- 当前桌面端不能直接完成 `BluFi` 配网
- 即使 USB 接在电脑上，Flutter 端也不会因为“串口在线”就显示击锤
- 只有成功加入同一局域网并发出 UDP 广播，桌面才会出现该击锤

## 预期日志

启动后应看到类似日志：

```text
Initializing WiFi BluFi provisioning...
SoftAP provisioning started: ssid=BianzongHammer-XXXXXX password=12345678 portal=http://192.168.4.1
BluFi provisioning started: device=BianzongHammer-XXXXXX
Dual provisioning ready: BluFi + SoftAP (BianzongHammer-XXXXXX)
Connecting to target WiFi SSID: ...
Got IP address: ...
SoftAP provisioning stopped
UDP socket initialized, broadcasting to 255.255.255.255:3333
BNO085 + DRV2605L motion-link test
feature ready sensor=8 interval=10000us
feature ready sensor=4 interval=5000us
Motion pipeline ready. Swing the mallet to trigger haptic pulses.
```

如果姿态和触觉链路正常，还会继续看到：

```text
pose yaw=... pitch=... roll=... | ang_vel=...
strike #1 tier=... effect=... pulse=ok yaw=... pitch=...
```

## 常见问题

- `手机 App 扫不到击锤`：先确认设备已上电、手机蓝牙已开启，并允许 App 使用蓝牙权限。
- `手机 App 配网后击锤不上线`：先确认目标 WiFi 是 `2.4GHz`，再确认密码正确。
- `手机无法用蓝牙完成配网`：可直接连接击锤热点 `BianzongHammer-XXXXXX`，密码 `12345678`，再打开 `http://192.168.4.1`。
- `手机 App 能连蓝牙但搜不到热点`：确认手机已完成蓝牙授权，同时查看串口是否打印 `BluFi request WiFi list`。
- `USB 已连接但桌面不显示击锤`：检查是否已经拿到 `Got IP address`，以及 Flutter 设备是否与击锤在同一 WiFi。
- `DRV2605L not found`：检查 GPIO20/GPIO19、供电、共地和 I2C 连线。
- `No valid BNO085 SHTP frame detected...`：检查 `PS0=3.3V`、`PS1=GND`、`TX->GPIO1`、`RX->GPIO2`。
