# 数字编钟击锤系统 PRD

> 项目代号：bianzhong-hammer-system
> 适用版本：固件 `bianzhong_hammer_uart_shtp` + 应用 `bianzhong_ninja_copy`
> 文档阶段：v1.0 草稿（待评审）
> 维护者：项目组

---

## 1. Problem Statement

用户希望以「真实挥动击锤」的方式演奏一座中国数字编钟：当观众把若干支 ESP32-S3 击锤（带 BNO085 姿态传感器 + DRV2605L 触觉马达）插在编钟架上挥舞时，桌面端或手机端的 App 应能即时识别每支击锤的姿态与挥动强度，并把它映射成编钟架上对应位置的一口钟，触发钟声、动画高亮与击锤端的触感反馈。但当前系统存在以下用户视角问题：

- **链路黑盒**：观众无法判断「为什么桌面没显示击锤」——是击锤没上电、BluFi 没配网、WiFi 没拿到 IP、还是 UDP 没广播。
- **配网入口单一**：桌面端无法触发 BluFi 配网，只能依赖手机或击锤热点；新增一支击锤时流程分散。
- **姿态到钟体的映射不可靠**：当前桌面端用「相对鼠标」算法把姿态差分映射到屏幕坐标，再做命中测试。当用户静止时仍然会因为噪声抖动产生光标漂移、误击；快速挥动时响应又不够快。
- **缺少触感回路闭环**：应用没有向击锤主动发送「该响了 / 该震一下」指令的成熟通道，导致击锤上的 DRV2605L 大多只用于击打瞬间的本地震动，没有承担「桌面提醒击锤挥动错误 / 命中边缘 / 跟随模式提示」等应用语义。
- **曲目跟奏模式薄弱**：仅有一首《小星星》、单音判定、无「侧击区域 / 升降半音 / 多人分工」语义，用户难以扩展。
- **多端兼容混乱**：同一份代码里同时存在 UDP 监听、BluFi 配网、WiFi 信息 native channel、nmcli 命令、legacy WebSocket 兼容逻辑、忍者模式轨迹 + 组合技，各种路径互不统一。

本次 PRD 目标：把硬件端与软件端整合成一套**端到端、可观测、可扩展、可测试**的「数字编钟击锤系统」，使任何使用者（观众 / 演奏者 / 维护者）都能在「开箱 → 配网 → 多人演奏 → 跟奏练习 → 离线排查」的完整路径上获得一致体验。

---

## 2. Solution

围绕一台「击锤 ↔ 应用」对等网络，把系统抽象成下面四个清晰的能力域，固件和应用都对应到这些能力域：

1. **发现与配网（Provisioning）**：击锤同时支持 BluFi（手机蓝牙）+ SoftAP + 微型门户网页（电脑兜底），并在 NVS 中保存 WiFi 凭据 / 击锤 ID / 已配网标志。应用端（手机 / 桌面 / Web）通过统一的服务发现入口接入，并对未配网击锤提供清晰的状态机和操作指引。
2. **姿态与击打采集（Motion Capture）**：击锤以 ≥100 Hz 读取 BNO085 的 `rotation vector` 与 `linear acceleration`，在本地完成 SLIP/SHTP 解析、四元数姿态解算、空挥角速度峰值检测、击打分级（Light / Medium / Heavy），并以 UDP `cursor` (30 Hz) + `strike` (事件) 广播给同网段所有订阅者。
3. **舞台与演奏（Stage & Performance）**：应用端将每支击锤作为一个独立 actor，按「相对鼠标式光标」映射到 12 钟体 + 3 区域（左/中/右）的舞台布局；接收 `strike` 事件时触发真实钟声、钟体高亮、`haptic` 回传指令、轨迹与组合技特效。同一台设备上多名演奏者按入网顺序自动获得「左/右手」座位。
4. **曲目与教学（Follow-along & Practice）**：应用内置可扩展的曲库（每首包含 note + 八度 + 节拍 + 击打区域），向演奏者高亮当前音，倒计时 3 秒开始播放，跟踪命中 / 失误率，并在曲目结束后给分。配合击锤上的 LED / 触感反馈告知演奏者「对 / 错」。

技术层面，本次 PR 不改变硬件选型（ESP32-S3、BNO085 UART-SHTP、DRV2605L I²C、WiFi 2.4 GHz），不引入新云服务，所有通信仍然走本地局域网 / 蓝牙 / 软 AP。

---

## 3. User Stories

### 3.1 开箱与首次配网

1. As a 演出观众, I want 一支全新的击锤上电后能被手机自动发现 so that 我不需要去记复杂的 WiFi 凭据就能完成配网。
2. As a 演出观众, I want 手机 App 明确显示「蓝牙配网中 / WiFi 连接中 / 已联网」三段进度 so that 我知道下一步该做什么。
3. As a 桌面用户, I want 当附近有未配网击锤时桌面 App 能提示我「该用手机扫码 / 连热点」 so that 我不会被卡在桌面端。
4. As a 击锤维护人员, I want 通过 192.168.4.1 网页就能填 SSID / 密码 so that 我可以在没有手机的情况下完成兜底配网。
5. As a 系统集成商, I want 配网后击锤自动关闭热点与门户 so that 用户不会长期暴露在陌生热点下。
6. As a 多击锤场地的运营人员, I want 同时为 12 支击锤配网时不必每支都点一遍 so that 我可以批量下发给所有 `BianzongHammer-*` 设备。

### 3.2 多人发现与入座

7. As a 现场演奏者, I want 桌面 App 在我挥动击锤那一刻就把我的击锤列出 so that 我能立刻确认「我已经在系统里了」。
8. As a 现场演奏者, I want 系统按照入网顺序自动给我分配「左 1 / 右 1 / 左 2…」的座位 so that 我不需要在 App 里手动登记自己是第几位。
9. As a 现场演奏者, I want 桌面 App 显示我的击锤 ID、deviceId、左右手 so that 我能和管理员沟通时精确定位自己。
10. As a 现场观众, I want 看到 12 支击锤的传感器数据实时刷新 so that 我能直观看到姿态在工作。
11. As a 现场演奏者, I want 我停止挥动 3 秒后桌面 App 自动把我的击锤从「活跃」列表移除 so that 屏幕不会被已下台的击锤占位。

### 3.3 演奏核心交互

12. As a 演奏者, I want 任意姿态挥动都被桌面 App 转成一次击钟事件 so that 我不需要真的敲到实体钟也能听到声音。
13. As a 演奏者, I want 轻挥 / 中挥 / 重挥对应不同音量与不同触感 so that 我的演奏力度有反馈。
14. As a 演奏者, I want 把击锤水平指向某口钟时，桌面端就锁定那口钟 so that 我能像真实舞台那样精准选钟。
15. As a 演奏者, I want 命中某口钟的「左 / 中 / 右」区域时，桌面播放对应音高 so that 我能像真实击钟那样有音色变化（侧击 = 上方大三度）。
16. As a 演奏者, I want 击锤本身在每次击中也震一下 so that 我手心能感受到节拍。
17. As a 演奏者, I want 桌面 App 在我「快挥但没到阈值」时回弹一次轻触感 so that 系统提示我「再用力一点」。
18. As a 演奏者, I want 切换八度时桌面端与击锤端同步 so that 我击打同一动作不会错位。
19. As a 现场观众, I want 桌面显示击锤光标轨迹 so that 我能看到挥动路径。

### 3.4 曲目与跟奏

20. As a 教学演奏者, I want 选择一首曲子后倒计时 3 秒自动播放 so that 我能跟得上节奏。
21. As a 教学演奏者, I want 当前应击打的钟在舞台上闪烁 so that 我不需要低头看屏幕就知道该击哪一口。
22. As a 教学演奏者, I want 我击中正确音时增加 hit、错过时增加 miss so that 结束后我能拿到一个准确率。
23. As a 演奏者, I want 跟奏模式中能暂停 / 继续 so that 我卡壳的时候可以缓冲一下。
24. As a 曲库管理员, I want 新增一首曲子只需在 JSON / Dart 常量里加一个 `Song` so that 我不需要写代码就能扩展曲目。
25. As a 演奏者, I want 曲目结束时能看到最终命中 / 失误 / 准确率 so that 我能评估自己的表现。

### 3.5 忍者 / 表演模式

26. As a 表演者, I want 在「忍者模式」下挥动时屏幕留出挥砍残影 so that 演出视觉更有冲击力。
27. As a 表演者, I want 残影轨迹在快速挥动时触发斩击判定 so that 我能像剑客那样连斩多口钟。
28. As a 表演者, I want 退出忍者模式后舞台回到标准钟体布局 so that 我能切回正常的跟奏模式。
29. As a 表演者, I want 多人同时开启忍者模式时不互相干扰 so that 每人的残影只对应自己的击锤。

### 3.6 设置与个性化

30. As a 用户, I want 在设置页调节整体音量 so that 我能配合场地大小调整。
31. As a 用户, I want 调高 / 调低挥动灵敏度 so that 我挥不动的时候也能触发，挥太灵敏时可以收窄。
32. As a 用户, I want 一键开关音效 so that 我可以静音只练动作。
33. As a 用户, I want 当前八度选择 (1–5) 持久化 so that 重启后还在我熟悉的八度。
34. As a 用户, I want 在设置页看到当前活跃击锤列表、WiFi SSID、固件版本 so that 我能向技术支持报问题。

### 3.7 可靠性、可观测、容错

35. As a 运维人员, I want 击锤断电 / 失联时桌面 App 在 3 秒内把它标为离线 so that 我能立刻看到网络状态。
36. As a 运维人员, I want 桌面 App 提供「重新搜索硬件 / 重启 UDP 监听」按钮 so that 我能在不退出应用的情况下恢复。
37. As a 运维人员, I want 击锤有串口日志输出 (BNO + DRV + WiFi + UDP 状态) so that 我能定位硬件问题。
38. As a 运维人员, I want 桌面 App 显示最近的错误消息 so that 用户能直接截图发给开发者。
39. As a 开发者, I want 桌面 App 与击锤之间所有 UDP 消息都有版本号字段 so that 未来升级协议时新旧固件可共存。
40. As a 开发者, I want 桌面 App 与击锤之间的事件流有可重放的环形缓冲 so that 出问题时我能回放最近 30 秒的击锤数据。

### 3.8 兼容与迁移

41. As a 老用户, I want 旧的 legacy WebSocket 连接方式仍然可以工作 so that 我不需要强制升级击锤固件。
42. As a 跨平台用户, I want 同一份击锤固件能同时被 Flutter 桌面 / 手机 / Web 端识别 so that 我能换设备而不换击锤。
43. As a 开发者, I want 桌面 App 内置一组 mock UDP 源 so that 我能在没有真实击锤的情况下完成 UI 调试。

### 3.9 安全

44. As a 系统集成商, I want BluFi 配网使用 device-name 前缀过滤 + proof-of-possession so that 现场不会被未授权设备蹭配网。
45. As a 用户, I want SoftAP 密码默认不是空 so that 现场 WiFi 不会被恶意连入。

---

## 4. Implementation Decisions

### 4.1 顶层架构（端到端对等模型）

把整个系统看作「**多个击锤 ↔ 一个应用**」的对等集合，所有能力都围绕一个明确的「事件总线」展开：

```
ESP32-S3 击锤                              Flutter 应用
  ┌────────────────────────┐                ┌─────────────────────────────┐
  │ 1. Provisioning       │ ─ BluFi/SoftAP →│ BleProvisioningService     │
  │   (BluFi + SoftAP +    │                │ ProvisioningRepository     │
  │    captive HTTP)        │                └─────────────────────────────┘
  │ 2. Motion Capture      │                ┌─────────────────────────────┐
  │   (BNO085 SHTP + DRV)   │ ─ UDP 3333 ──→│ UdpHammerService            │
  │ 3. Strike Detection    │                │ HammerPoseMapper            │
  │   (角速度峰值 + 分级)    │                │ StageHitMapper              │
  │ 4. Local Haptics       │                └─────────────────────────────┘
  │   (DRV2605L LRA)        │                ┌─────────────────────────────┐
  │ 5. Outbound Haptics    │ ←─ UDP 3333 ───│ HapticCommandChannel        │
  │   (应用语义回传)         │                │ (回传触感 / 提示 / LED)     │
  └────────────────────────┘                └─────────────────────────────┘
```

明确的设计原则：

- **事件总线即协议**：所有跨网络通信都收敛在 UDP `:3333` 上的 JSON 信封（`type` + `id` + `deviceId` + `timestamp` + payload），新能力通过新增 `type` 而非新通道扩展。
- **击锤永远是被动广播者**：UDP 只出不进；任何下行指令（触感 / LED / 配置）通过单独的短连接 UDP 命令通道回送，避免广播风暴。
- **应用永远是单一订阅者**：UdpHammerService 在应用进程内是单例，提供 `messageStream`、`activeHammerStream`、`commandSink` 三个 stream，对外隐藏 socket 细节。

### 4.2 共享类型与协议契约

- 定义 `HammerMessage` 协议版本字段 `proto: 1`；所有现有 `cursor` / `strike` / `haptic` 都带 `proto`；新增字段必须有默认值以保持兼容。
- 击锤 ID 统一为 1–12（与 NVS 配置一致），由击锤本地随机生成；deviceId 取 ESP32 MAC 后 6 位（与 `shortDeviceId` 一致）。
- 应用侧把姿态投影坐标统一用「归一化 0..1」表达，便于跨分辨率渲染。
- 八度语义统一为 1–5（共 60 钟体 = 5 八度 × 12 半音），由 `BellMapping` 单一权威维护；任何 UI / 音频 / 触感都基于 `bellId` 取映射。

### 4.3 模块拆分（要新建 / 强化的深度模块）

#### 击锤固件侧（bianzhong_hammer_uart_shtp）

| 模块 | 角色 | 关键接口 / 数据 |
|---|---|---|
| `Bno085Link` | 把 SH2 / SLIP / UART 解析、feature ready、reset 等所有传感器相关状态机收口 | `init() → bool`、`onRotationVector(cb)`、`onLinearAccel(cb)`、`stats()` |
| `MotionPipeline` | 把四元数 + 角速度 + 角加速度 + 线性加速度组合成 SwingPhase + StrikeTier，输出 `MotionSample` | `step(sample) → MotionEvent`、`reset()` |
| `Drv2605` | 封装 LRA 配置 + effect 触发 + busy 轮询 + fallback | `configure()→bool`、`pulse(tier)→PulseResult` |
| `WifiProvisioner` | BluFi / SoftAP / STA 切换状态机 + NVS 持久化 + captive portal HTTP | `init()→ProvisionState`、`apply(ssid,pass)→ProvisionOutcome` |
| `UdpBus` | JSON 信封构造 + 发送 + 命令监听 | `publishCursor(sample)`、`publishStrike(event)`、`onCommand(cb)` |
| `OctaveSwitcher` | 4 路 GPIO 按键 → 八度 + 应用端同步广播 | `init()→void`、`currentOctave()` |

Bno085Link 是这套系统的「深模块」候选：对外只暴露「给我一个旋转 / 给我一个线加速度 / 当前 IMU 是否健康」，内部封装 SLIP 状态机、波特率自适配、`feature ready` 协议，外部测试不需要关心。

#### 应用侧（bianzhong_ninja_copy）

| 模块 | 角色 | 关键接口 / 数据 |
|---|---|---|
| `HammerDiscoveryRepository` | 把 BLE 扫描、WiFi 扫描、UDP 监听、当前 SSID 等多源信息聚合成一个「击锤清单」数据源 | `Stream<List<HammerView>>`、`scan()`、`currentSsid()` |
| `UdpHammerService` | 单 socket 监听 UDP `:3333`，按 `deviceId` 维护活跃击锤、超时回收、上限 12 | `start() / stop() / restart()`、`messageStream`、`activeHammerStream` |
| `HammerPoseMapper` | 把四元数 / 欧拉角转成「相对鼠标」光标点，自带速度自适应死区与平滑 | `update(deviceId, …) → HammerPoseProjection` |
| `StageHitMapper` | 把光标点 / 轨迹段映射到钟体 + 区域（center / left / right） | `hitTestStagePoint`、`hitTestTrailSegments` |
| `StrikeRouter` | 输入：UdpHammerMessage；输出：是否触发击钟、bellId、强度、是否回传 haptic | `route(msg) → StrikeDecision` |
| `HapticCommandChannel` | 把应用侧语义（命中边缘 / 错误 / 教学模式提示）打包成 UDP 下行命令 | `send(hapticCommand)` |
| `StageRenderer` | CustomPainter 绘制钟架、钟体、高亮、轨迹、跟奏闪烁 | `paint(canvas, size, state)` |
| `FollowAlongRunner` | 曲目播放、倒计时、节拍、命中判定、最终统计 | `start(songId) / pause / resume / stop()` |
| `AudioEngine` | 16 声部复用、`BellMapping` 资产解析、音量 / 静音 | `playBell(bellId, intensity)` |
| `SettingsRepository` | 持久化音量、灵敏度、八度、模式、WiFi 凭据候选 | `get / set / listen` |
| `MockHammerSource` | 测试 / 演示用，合成的 UDP 消息源（环形缓冲 + 录制回放） | `start() / stop()` |

StrikeRouter 是这套应用的「深模块」候选：它接收一份 `UdpHammerMessage` 并发出 `StrikeDecision { bellId, region, intensity, hapticHint }`，内部把「UDP 击打判定」「姿态累计 gesture strike」「忍者模式斩击」「跟奏命中判定」四套策略收敛为单一决策点；UI 层不再需要 if/else 组合。

### 4.4 关键技术决策

#### 4.4.1 击打判定策略（多源融合）

把击打判定收敛在 StrikeRouter 内部，按以下顺序组合（任一为真即触发）：

1. **击锤上行 `strike` 事件**：`force` 已分级，使用 bellId（由映射阶段计算）+ region + intensity；UI 层只接受。
2. **应用端 `gesture strike`**：连续 N ms 锁定同一 strike 区域 + 角速度 ≥ 阈值 + 向下速度 ≥ 阈值；用于击锤未发 `strike` 事件但光标已进入区域的「补判」。
3. **忍者模式 `slash`**：斩击轨迹段与钟体区域相交，产生 1..N 次击打，每口钟只触发一次。
4. **跟奏命中**：在跟奏窗口期内若击打的 bellId 与当前期望 bellId 匹配，仅记录命中与播放，不重复音频。

防抖：每个 deviceId 维护 `_lastAcceptedStrikeAt`，默认 180 ms（沿用 `uiStrikeDebounce`）。

#### 4.4.2 姿态映射算法

- 保留现有「相对鼠标」思路（`HammerPoseMapper`），但显式拆出 `_DeviceState` 的内部契约，并提供 `recenter(deviceId)` 给 UI 调用（校准按钮）。
- 自适应死区阈值与平滑系数在 `HammerPoseMapper` 内部以常量集中维护；不再散落到 `AppProvider`。
- 在静止态（角速度 < 12°/s）下，光标完全锁死，避免噪声漂移；测试中需要覆盖此场景。

#### 4.4.3 触感回路（Haptic round-trip）

- 新增 `HapticCommandChannel`，使用与上行 UDP 不同的「短命令端口」（例如 3334）作为下行通道；击锤固件监听该端口并把 JSON 命令路由到 `Drv2605` 或 LED。
- 应用侧触发回传的语义集合最小集合：`on_strike_ok`、`on_strike_miss`、`on_octave_change`、`on_follow_note_hit`、`on_follow_note_miss`。每个语义映射到一组 DRV2605 effect id + 强度。
- 击锤侧把每个下行命令落地为一次 `trigger_drv2605_effect`，并在 `haptic_command_count` 计数 + 日志，便于现场核对「应用到底有没有下发命令」。

#### 4.4.4 配网状态机

- 击锤侧把配网过程拆为 `Ready → Applying → Connecting → GettingIp → Connected → Failed`，每个阶段由 `set_provision_stage(stage, message)` 统一驱动：
  - 串口日志（详情）
  - SoftAP 门户 JSON `/api/status`（用于桌面 / 网页查询进度）
  - BluFi `configure_params` 事件（用于手机 App 展示）
- 应用侧把当前阶段映射为一个枚举 + 进度条 + 状态文案，避免每个调用方自己拼接字符串。
- NVS 写入只在 `Connected` 成功后落盘；中途断电不会留下半配网状态。

#### 4.4.5 多端入口差异

- 桌面端：仅支持 WiFi 信息查询（`nmcli` / Win32 `netsh`） + UDP 监听 + 网页兜底；明确禁用 BluFi 入口并提示用户「请用手机 App 完成蓝牙配网」。
- 手机端：完整 BluFi 入口 + WiFi 直连入口（`MethodChannel`）。
- Web 端：仅支持 UDP 监听（浏览器能力所限）。

这条决策保证「功能矩阵」一致，不再在 `BleProvisioningService` 里散落 `Platform.isAndroid` 分支。

#### 4.4.6 曲目数据模型

- `Song` 当前已是不可变值对象；保持这种风格，把曲库改为 JSON 资源（`assets/songs/<id>.json`），Dart 端只负责反序列化。
- `SongNote` 新增 `region`（默认 `center`）、`velocityHint`（默认 0.8），允许曲目为某些音指定「侧击 / 强击」。
- 跟奏运行时不再依赖单首《小星星》；`SongLibrary` 改为扫描所有 `assets/songs/*.json`。

#### 4.4.7 渲染与节流

- 引入 `stageRevisionListenable`（已存在）+ `ValueNotifier<int>` 让舞台只重绘变化的图层。
- 30 Hz 是 cursor 上行目标；渲染层接受任意频率但内部节流到 60 FPS。
- 钟体高亮使用「相对时间」而非绝对时间，避免设备卡顿后高亮恢复时跳变。

### 4.5 协议示例（共享）

```jsonc
// 击锤 → 应用 (cursor, 30 Hz)
{
  "proto": 1,
  "type": "cursor",
  "id": 3,
  "deviceId": "A1B2C3",
  "yaw": 12.3, "pitch": -4.5, "roll": 1.1,
  "quaternion": {"w": 0.99, "x": 0.01, "y": 0.04, "z": 0.02},
  "angularVelocity": 380.2,
  "angularAcceleration": 110.5,
  "accelMagnitude": 1.023,
  "linearAcceleration": {"x": 0.1, "y": 0.2, "z": 0.97},
  "octave": 3,
  "timestamp": 1737189123456789
}

// 击锤 → 应用 (strike, 事件)
{
  "proto": 1,
  "type": "strike",
  "id": 3, "deviceId": "A1B2C3",
  "force": 0.74, "tier": "medium",
  "yaw": 12.3, "pitch": -4.5, "roll": 1.1,
  "quaternion": {"w": 0.99, "x": 0.01, "y": 0.04, "z": 0.02},
  "angularVelocity": 612.3,
  "octave": 3,
  "timestamp": 1737189123499000
}

// 应用 → 击锤 (haptic 命令)
{
  "proto": 1,
  "type": "haptic",
  "id": 3,                       // 目标 hammerId
  "semantic": "on_strike_ok",    // 应用语义
  "tier": 2,                     // 1=light / 2=medium / 3=heavy
  "intensity": 0.6,
  "bellId": 27
}
```

`proto` 字段由本次 PR 引入；新版本固件 / 应用必须填写，旧版本忽略即可保持兼容。

### 4.6 数据 / 资产组织

- `assets/audio/`：保持现状（按 `bell_*.wav` 命名），`BellMapping.resolveAssetFileName` 仍负责兜底匹配。
- `assets/songs/`：新增；曲目 JSON 在启动期一次性加载。
- 桌面端不再依赖 WebSocket，仅在「legacy mode」开关打开时启用，便于兼容未升级固件的老击锤。

### 4.7 不变量

- 任何路径下 `bellId` 都属于 `[1, 60]`；超出即视为无效并丢弃。
- 任何路径下 `hammerId` 都属于 `[1, 12]`；超出即视为无效并丢弃（与击锤固件 NVS 限制一致）。
- 应用侧 `currentOctave ∈ [1, 5]`；击锤侧 GPIO 按下后会先 `clamp` 再上行。
- DRV2605L 在收到 `pulse` 命令前必须完成 LRA 配置；任何 `pulse` 失败要回退到 `DRV_EFFECT_FALLBACK`，并把回退结果计入日志。

---

## 5. Testing Decisions

### 5.1 测试原则

- **只测外部行为**：模块的对外契约（公开方法 / Stream / 协议字段）才是测试目标；内部 SLIP 解析、姿态滤波细节不直接断言。
- **确定性**：所有依赖时间 / 随机 / socket 的模块都通过显式接口注入 `Clock`、`RandomSource`、`UdpSocket` 抽象。
- **协议一致性**：固件 JSON 与 Dart `UdpHammerMessage.fromJson` 之间使用共享的 golden fixture（保存在 `test/fixtures/udp_messages.json`），任何字段重命名都要更新两侧。
- **离线可跑**：所有应用层测试不能依赖真实击锤；通过 `MockHammerSource` 注入合成数据。

### 5.2 优先测试的模块

按「投资回报」排序，先测：

1. **`StrikeRouter`**：纯函数式输入输出，覆盖：UDP `strike` 直接通过 / 区域不命中 / 跟奏窗口命中 / 忍者斩击命中 / 防抖抑制；测试断言 `StrikeDecision` 的 bellId / region / intensity / hapticHint。
2. **`HammerPoseMapper`**：覆盖静止锁死、慢速移动、急速挥动、断流复位、超时复位；断言 `displayPoint` 在归一化坐标内单调平滑。
3. **`StageHitMapper`**：覆盖 12 钟体 × 3 区域的全部命中组合；用 golden image 测试留作可选。
4. **`UdpHammerService`**：用 `MockRawDatagramSocket` 注入合成数据报；覆盖超时不活跃、上限 12、协议错包忽略。
5. **`Bno085Link`**（固件）：在 host 上跑 SH2 解析，用录制 SHTP 字节流做回归；不需要真 IMU。
6. **`Drv2605`**：在 host 上 mock I²C，覆盖 busy / fallback / LRA 配置失败。
7. **`FollowAlongRunner`**：覆盖曲目节拍、命中判定、暂停 / 继续 / 完成态。
8. **`BellMapping`**：覆盖 `getBellId`、`resolveAssetFileName` 兜底、`nextTwoScaleStepsBellId`。

### 5.3 测试形式

- 应用侧：Dart `flutter_test`，外加 `test/runner` 入口运行所有非 UI 测试；UI 测试仅对 `HomeScreen`、`SettingsScreen` 做关键路径冒烟。
- 固件侧：使用 ESP-IDF 的 `unity` 框架，把可纯函数化的部分抽到 host 编译目标（`#ifdef HOST_TEST`）；SH2 解析 / 姿态流水线都用 fixture 字节流做回归。

### 5.4 测试 Fixture 与回放

- `test/fixtures/udp_messages/`：收集现场抓取的 UDP 报文，供应用回归使用。
- `test/fixtures/shtp_frames/`：收集 BNO085 上电 → rotation vector 启动 → linear accel 启动的字节流，供固件 SH2 解析回归。

### 5.5 端到端冒烟

- 在 CI 中执行 1 分钟冒烟：模拟 UDP 源连续发送 cursor/strike，断言应用侧 `_handleStrike` 被调用次数、AudioEngine 被请求播放的 bellId 序列、跟奏命中统计。
- 固件侧执行 build 验证（不烧录），保证 `idf.py build` 在 PR 流水线内通过。

---

## 6. Out of Scope

本次 PRD 不包含：

- **真实物理击打检测**：当前为「空挥角速度」方案，不引入加速度冲击阈值或外部冲击传感器；后续 PR 再评估。
- **多人 WiFi 直连 / 离线路由**：击锤之间不互相通信，全部经应用。
- **云端账户 / 演出录像上传**：所有内容仅本地。
- **Web 端 BluFi 配网**：浏览器无 BLE Host 能力，配网仍需手机。
- **新音频合成 / 音色扩展**：不引入新 `.wav` 资产；现有 `BellMapping.resolveAssetFileName` 兜底保留。
- **跨平台触觉 API**：仅做 DRV2605L；不引入 Android Vibrator / iOS CoreHaptics。
- **多人账号 / 权限系统**：当前假设单机本地使用。
- **曲目自动生成 / AI 跟奏评估**：仅做规则判定。
- **硬件变更**：不更换 BNO085 / DRV2605L / ESP32-S3 选型，不增加 LED 灯条 / 蜂鸣器 / 屏幕。
- **协议加密**：UDP 明文 + 仅本地网络；后续若要进入公网演示再单独评估。

---

## 7. Further Notes

- **性能预算**：UDP `cursor` 30 Hz × 12 击锤 = 360 pkt/s，单包 ~250B；峰值 ~900 kbps，远低于 2.4G WiFi 上限。
- **音频资源大小**：现有 `assets/audio/` 约 2–3 MB，已纳入 APK / 安装包体积预算；若后续扩展 60 口 → 全 5 八度，按需切片。
- **回归风险面**：StrikeRouter / PoseMapper / HitMapper 是改动最大区域；优先在 `test/` 内固化测试用例，避免回归。
- **国际化**：当前文案主要为简体中文；多语言通过 Flutter `intl` 抽离，预留 `.arb` 资源入口。
- **可视化可观测**：建议在桌面端调试模式提供「最近 30 秒 UDP 报文时间线」面板，用于现场排查。
- **里程碑建议**：
  1. 协议版本字段 + StrikeRouter 重构 + 既有测试补齐（先收敛「决策点」）。
  2. HapticCommandChannel + 击锤固件下行通道。
  3. 曲库 JSON 化 + FollowAlongRunner 升级。
  4. MockHammerSource + E2E 冒烟。
  5. 配网状态机统一与 NVS 持久化加固。

> 以上决策待项目组评审；任一用户故事均可独立切分为 tracer-bullet 实施切片。