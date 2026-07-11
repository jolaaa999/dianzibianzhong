# 虚拟数字编钟 — 前端开发文档

| 属性 | 值 |
|------|-----|
| 文档版本 | v2.1 |
| 适用工程 | `bianzhong_ninja_copy/`（包名 `bianzhong_app`） |
| 关联 PRD | `electronic-bianzhong-prd-v1(1).docx` v1.0（方案一：低成本视觉追踪） |
| 关联文档 | `PROJECT_OVERVIEW.md` |
| 最后更新 | 2026-07-09 |

---

## 文档结构说明

本文档分为 **两大部分**：

| 部分 | 标题 | 内容 |
|------|------|------|
| **第一部分** | 已实现内容 | 当前 `bianzhong_ninja_copy` 源码中 **已完成、可运行或基本可用** 的前端功能规格 |
| **第二部分** | 未实现内容 + 开发步骤 | PRD 差距、分模块 **逐步开发指南**、验收清单、路线图（§11~§22） |

> **重要说明**：当前代码走的是 **ESP32 IMU 击锤 + Flutter 桌面** 路线；PRD 方案一核心是 **USB 摄像头 + 反光标记 + 视觉坐标输入**。PRD **未硬性规定**客户端必须用浏览器（该条为待确认假设，Electron/Flutter 桌面均可）。第一部分描述「现状」，第二部分描述「目标差距 + 逐步开发指南」。

---

## 总览：实现进度对照表

| PRD 模块 | 第一部分（已实现） | 第二部分（未实现） |
|----------|-------------------|-------------------|
| 编钟展示界面 | ✅ 完整 | 半弧形布局微调、调试碰撞盒 |
| 敲击检测与反馈 | ✅ IMU/触控版 | ❌ 视觉坐标版 |
| 声音合成引擎 | ⚠️ 基础播放 | ❌ DRC/混响/音量平衡 |
| 通信中间件 | ✅ UDP + WebSocket | ❌ PRD stick 协议 |
| 视觉追踪系统 | — | ❌ 全部 |
| 系统校准向导 | — | ❌ 全部 |
| 演示模式控制 | — | ❌ 全部 |
| IMU 专属功能 | ✅ 忍者/跟奏/配网 | — |

---

# 第一部分：已实现内容

> 本部分描述当前工程中 **已经落地** 的前端/客户端能力，开发者可据此维护、联调与二次开发。

---

## 1. 项目概况（现状）

### 1.1 技术路线

- **客户端**：Flutter 3.x 多平台应用（当前主要跑 **Windows 桌面**）
- **输入硬件**：ESP32-S3 智能击锤（BNO085 IMU）
- **主通信**：UDP 3333 JSON 广播
- **兼容通信**：WebSocket `ws://192.168.4.1:81`
- **状态管理**：`provider` + `AppProvider`

### 1.2 运行状态

| 项 | 状态 |
|----|------|
| Windows 桌面编译运行 | ✅ 已验证（`flutter run -d windows`） |
| 主界面 / 编钟舞台渲染 | ✅ |
| 鼠标/触控敲击 | ✅ |
| UDP 击锤输入（代码层） | ✅ |
| 音频播放（代码层） | ✅ |
| 音频资源文件 | ⚠️ `assets/audio/` 可能为空，需补资源 |

### 1.3 术语表

| 术语 | 含义 |
|------|------|
| bellId | 编钟唯一编号，1~60（5 八度 × 12 音） |
| 舞台坐标 | 归一化 `(stageX, stageY)`，范围 0~1 |
| 击锤 / Hammer | ESP32 智能敲击棒，IMU 上报姿态 |
| 侧击区域 | 钟面左/中/右三区，侧击触发转调 |
| 忍者模式 | 挥砍轨迹连击多钟 |
| 跟奏模式 | 按曲谱节拍引导敲击 |

---

## 2. 技术架构（已实现）

### 2.1 技术栈

```
Flutter 3.x (Dart ^3.11.5)
├── provider              全局状态
├── audioplayers          音频播放（16 复音）
├── web_socket_channel    WebSocket 兼容
├── shared_preferences    本地配置
└── esp_blufi_for_flutter 蓝牙配网（third_party）
```

### 2.2 分层架构

```
Presentation   screens/  widgets/
Application    providers/app_provider.dart
Domain/Utils   hammer_pose_mapper  stage_hit_mapper  slash_detector  blade_trail
Infrastructure udp_hammer_service  websocket_service  audio_service  ble_provisioning
```

### 2.3 目录与入口

| 路径 | 职责 |
|------|------|
| `lib/main.dart` | 入口，`MaterialApp` + `ChangeNotifierProvider` |
| `lib/screens/` | 页面：Home / Settings / Connection / FollowAlong |
| `lib/widgets/` | 组件：StageBianzhongView 等 |
| `lib/providers/app_provider.dart` | **业务中枢** |
| `lib/services/` | UDP / WebSocket / 音频 / 蓝牙 |
| `lib/utils/` | 碰撞检测、姿态映射、常量 |

**启动流程：**

```
main() → AppProvider 构造
  ├─ _initializeBellStates()      // 60 钟状态
  ├─ _setupListeners()            // 订阅 UDP/WS
  └─ startHardwareDiscovery()     // 自动监听 UDP 3333
→ HomeScreen → StageBianzhongView
```

---

## 3. 页面与导航（已实现）

### 3.1 页面地图

```
HomeScreen（默认首页）
├── AppBar：水果忍者 / 智能跟奏 Chip
├── AppBar：设置 → SettingsScreen
├── Body：StageBianzhongView
└── Overlay：跟奏倒计时

SettingsScreen
├── 音频 / 灵敏度设置
├── 配网与连接 → ConnectionScreen
└── 测试播钟 / 关于

ConnectionScreen
├── UDP 广播监听
└── WebSocket 兼容连接
```

### 3.2 页面规格

| 页面 | 文件 | 状态 |
|------|------|------|
| HomeScreen | `home_screen.dart` | ✅ 已接入主导航 |
| SettingsScreen | `settings_screen.dart` | ✅ |
| ConnectionScreen | `connection_screen.dart` | ✅ |
| FollowAlongScreen | `follow_along_screen.dart` | ⚠️ 已实现但未接入主导航 |

### 3.3 设计规范

| 属性 | 值 |
|------|-----|
| 设计系统 | Material 3，种子色 amber |
| 响应式断点 | 960px / 760px |
| 编钟高亮色 | 默认铜色 / 激活金色 / 跟奏琥珀色 |
| 舞台布局 | 上下两排 12 钟，归一化坐标 0~1 |

---

## 4. 全局状态管理（已实现）

### 4.1 AppProvider 核心字段

**连接：** `connectionStatus`、`activeHammers`、`connectionSummary`  
**演奏：** `currentOctave`、`activeBellIds`、`volume`、`sensitivity`  
**模式：** `ninjaMode`、`followProgress`、`currentSong`  
**配网：** `bleDevices`、`isBleProvisioning`

### 4.2 公开方法

| 方法 | 用途 |
|------|------|
| `onBellTapped(bellId, intensity, {region})` | 屏幕敲击 |
| `startFollowAlong(songId)` | 开始跟奏 |
| `ninjaMode = true/false` | 忍者模式 |
| `startHardwareDiscovery()` | UDP 监听 |
| `connectLegacyWebSocket(url)` | 旧版 WS |
| `scanBleProvisionDevices()` | 蓝牙扫描（移动端） |

### 4.3 舞台刷新机制

- 高频刷新用 `stageRevisionListenable`（ValueNotifier），约 33ms
- 普通设置变更用 `notifyListeners()`

---

## 5. 核心组件（已实现）

### 5.1 StageBianzhongView（核心舞台）

**文件：** `lib/widgets/stage_bianzhong_view.dart`

| 能力 | 状态 |
|------|------|
| CustomPaint 绘制 12 钟面 + 钟架 | ✅ |
| 鼠标/触控 Pointer 敲击 | ✅ |
| 硬件击锤光标/瞄准高亮 | ✅ |
| 左/中/右三区域碰撞检测 | ✅ |
| 敲击高亮 300ms | ✅ |
| 击锤下砸动画 180ms | ✅ |
| 跟奏目标钟闪光 | ✅ |
| 忍者模式刀光轨迹 | ✅ |

**钟面布局（当前八度 12 音）：**

| 层 | 音名 |
|----|------|
| 下层 | C D E F G A B |
| 上层 | C# D# F# G# A# |

### 5.2 其他已实现组件

| 组件 | 文件 | 状态 |
|------|------|------|
| _ModeChip | `home_screen.dart` 内联 | ✅ 使用中 |
| BellGridWidget | `bell_grid_widget.dart` | ✅ 代码完成，未引用 |
| BleProvisionSheet | `ble_provision_sheet.dart` | ✅ 代码完成，入口未接 |
| ConnectionStatusWidget | `connection_status_widget.dart` | ✅ 代码完成，未引用 |

---

## 6. 输入与通信（已实现）

### 6.1 输入源

| 输入源 | 服务 | 状态 |
|--------|------|------|
| UDP 击锤 | `UdpHammerService` | ✅ 主路径 |
| WebSocket | `WebSocketService` | ✅ 兼容 |
| 屏幕/鼠标 | `StageBianzhongView` | ✅ |

### 6.2 UDP 协议（击锤 → 客户端）

**端口：** 3333

```json
{
  "type": "strike",
  "id": 1,
  "deviceId": "esp32-abc123",
  "octave": 3,
  "yaw": 12.5, "pitch": -8.2, "roll": 1.0,
  "quaternion": { "w": 0.99, "x": 0.01, "y": 0.05, "z": 0.02 },
  "force": 0.75,
  "timestamp": 1710000000123456
}
```

### 6.3 数据处理管线

```
UDP → HammerPoseMapper → StageHitMapper → 敲击判定 → AudioService + 高亮
```

### 6.4 敲击判定参数

| 参数 | 值 |
|------|-----|
| 最低敲击强度 | 0.12 |
| 防抖间隔 | 180ms |
| 高亮持续 | 300ms |
| 最大击锤数 | 12 |
| 击锤超时 | 3s |

---

## 7. 音频系统（已实现 · 基础版）

| 能力 | 状态 |
|------|------|
| 60 bellId 音域映射 | ✅ |
| 16 路 AudioPlayer 复音池 | ✅ |
| 按 bellId 匹配 WAV 资源 | ✅ |
| 侧击转调（跳两个音阶） | ✅ |
| 音量 × 强度调节 | ✅ |

**bellId 公式：** `(octave - 1) × 12 + noteIndex + 1`

---

## 8. 交互模式（已实现）

### 8.1 普通演奏（默认）

击锤 / 鼠标 / 触控 → 单点碰撞 → 单音 + 高亮

### 8.2 水果忍者模式

- 入口：HomeScreen AppBar Chip
- 角速度 ≥ 100°/s 判定挥砍
- 刀光轨迹碰撞多钟连击
- 与跟奏互斥

### 8.3 智能跟奏模式

- 入口：HomeScreen 选曲弹窗
- 3 秒倒计时 → 按 BPM 推进音符
- 统计 hit / miss / accuracy
- 曲库：目前仅「小星星」

### 8.4 模式互斥

忍者 ↔ 跟奏互斥；开启跟奏会关闭忍者。

---

## 9. 平台与部署（已实现）

### 9.1 平台能力

| 能力 | Windows | Android/iOS |
|------|---------|-------------|
| UDP 监听 | ✅ | ✅ |
| WebSocket | ✅ | ✅ |
| 蓝牙配网 | ❌ | ✅（代码已有） |
| 桌面运行 | ✅ 已验证 | — |

### 9.2 本地运行

```bash
cd bianzhong_ninja_copy
flutter pub get
flutter run -d windows
```

**前置条件：** Flutter SDK、Visual Studio C++、Windows 开发者模式。

### 9.3 构建发布

```bash
flutter build windows --release
```

---

## 10. 已实现内容的维护指南

### 10.1 关键文件索引

| 文件 | 职责 |
|------|------|
| `app_provider.dart` | 业务中枢 |
| `stage_bianzhong_view.dart` | 编钟舞台 |
| `stage_hit_mapper.dart` | 碰撞检测 |
| `hammer_pose_mapper.dart` | IMU → 坐标 |
| `udp_hammer_service.dart` | UDP 协议 |
| `audio_service.dart` | 音频播放 |
| `constants.dart` | 常量 + BellMapping |

### 10.2 常见维护操作

- **改舞台布局**：同步修改 `stage_bianzhong_view.dart` 与 `stage_hit_mapper.dart`
- **加跟奏曲**：编辑 `song_library.dart`
- **调试 UDP**：Settings → 连接信息；或 netcat 发 JSON 到 3333

### 10.3 已实现但需注意的问题

| 问题 | 说明 |
|------|------|
| 音频资源可能缺失 | 需补 `assets/audio/*.wav` |
| FollowAlongScreen 未接导航 | 跟奏入口仅在 Home 弹窗 |
| BleProvisionSheet 无入口 | 配网 UI 未集成到 ConnectionScreen |
| BellGridWidget 未使用 | 可考虑删除或作调试页 |
| audioplayers 线程警告 | Windows 控制台有 WARN，暂不影响使用 |

---

# 第二部分：未实现内容（含详细开发步骤）

> 本部分列出 **PRD 方案一** 及工程规划中尚未完成的功能，并为每一项提供 **可执行的开发步骤、涉及文件、验收标准**，便于按图施工。

---

## 11. 与 PRD 方案一的核心差距

### 11.1 PRD 确定了什么、没确定什么

| 类别 | PRD 内容 | 说明 |
|------|----------|------|
| **已确定（方案一核心）** | USB 摄像头 + 反光标记 + OpenCV 追踪 | 后端/算法侧，非纯前端 |
| **已确定** | 输出 stick 二维坐标至展示界面 | 前端需消费 x/y |
| **已确定** | 编钟展示、敲击检测、音频、校准、演示模式 | 功能模块清单 |
| **待确认 [Assumption]** | 浏览器网页优先 / Electron 兼容 | **非强制 Web** |
| **待确认 [Assumption]** | WebSocket 或串口通信 | 桌面可用 WS 或串口 |
| **待确认 [Assumption]** | 编钟数量 8~12、速度阈值等参数 | 联调时定 |

当前 Flutter 桌面 **不违反 PRD**；差距主要在 **输入源（视觉 vs IMU）** 和部分 **展厅模块未做**。

### 11.2 差距总表

| PRD 模块 | 方案一要求 | 当前状态 | 优先级 | 详见章节 |
|----------|-----------|----------|--------|----------|
| 视觉追踪输入 | stick x/y 实时推送 | ❌ | P0 | §12、§13 |
| 敲击检测（视觉版） | 速度曲线判定敲击 | ❌ | P0 | §13 |
| 通信中间件（stick） | WS/串口 + 重连 | ⚠️ 仅有 IMU 协议 | P0 | §12 |
| 编钟展示增强 | 瞄准提示、200ms 振动动画 | ⚠️ 部分有 | P1 | §14 |
| 系统校准向导 | 三步向导 | ❌ | P1 | §15 |
| 演示模式控制 | 待机/attract loop | ❌ | P1 | §16 |
| 音频 DRC/混响 | 多音平衡 | ❌ | P2 | §17 |
| 现状补齐 | 音频资源、UI 集成等 | ⚠️ | P0 | §18 |

### 11.3 推荐开发顺序（依赖关系）

```
§18 现状补齐（音频、UI 集成）
    ↓
§12 VisionTrackingService + 协议联调
    ↓
§13 视觉敲击检测引擎
    ↓
§14 舞台瞄准/动画增强 + §19 Debug 碰撞盒
    ↓
§15 校准向导
    ↓
§16 演示模式
    ↓
§17 音频高级混音
```

---

## 12. 视觉追踪通信层 — 开发指南

**目标：** 接收 Python/OpenCV 追踪服务推送的 stick 坐标，转为 Flutter 内统一数据结构。

**原则：** 只新增输入层，**复用** `StageHitMapper` → `AppProvider._handleStrike()` 链路。

### 12.1 前置条件

- [ ] 与算法/后端同学确认 WebSocket 地址（如 `ws://127.0.0.1:8765`）
- [ ] 确认坐标系：x/y 是否为 **0~1 归一化**（相对舞台区域，非像素）
- [ ] 确认推送频率：30~60Hz
- [ ] 确认 stick_id：1=左棒，2=右棒

### 12.2 涉及文件（新建）

| 文件 | 职责 |
|------|------|
| `lib/models/vision_stick_frame.dart` | 数据模型 |
| `lib/services/vision_tracking_service.dart` | WS 连接、解析、流推送 |
| `lib/utils/constants.dart` | 新增 `defaultVisionWsUrl` 等常量 |

### 12.3 步骤 1：定义数据模型

创建 `lib/models/vision_stick_frame.dart`：

```dart
class VisionStickFrame {
  final int stickId;       // 1 或 2
  final double x;          // 0~1
  final double y;          // 0~1
  final double confidence; // 0~1
  final DateTime timestamp;
  final bool isVisible;    // 降级：追踪丢失时为 false

  const VisionStickFrame({...});

  factory VisionStickFrame.fromJson(Map<String, dynamic> json) {
    // 解析 timestamp, stick_id, x, y, confidence
    // 可选字段 visible / lost
  }
}
```

**验收：** 单元测试能正确解析 PRD 示例 JSON。

### 12.4 步骤 2：实现 VisionTrackingService

参考现有 `WebSocketService` 结构，创建 `vision_tracking_service.dart`：

| 能力 | 实现要点 |
|------|----------|
| `connect(url)` | 使用 `web_socket_channel`，连接成功后 `_updateStatus(connected)` |
| `frameStream` | `StreamController<VisionStickFrame>.broadcast()` |
| 心跳/断线 | 5s 无数据 → `reconnecting`；自动重连间隔 3s |
| 解析 | `_onMessage` 内 `VisionStickFrame.fromJson` |
| 降级 | stick 数量 ≠ 2 时，缺失 stick 发 `isVisible: false` |

**在 `AppConstants` 新增：**

```dart
static const String defaultVisionWsUrl = 'ws://127.0.0.1:8765';
static const Duration visionFrameTimeout = Duration(milliseconds: 200);
static const Duration visionReconnectDelay = Duration(seconds: 3);
```

### 12.5 步骤 3：AppProvider 接入

修改 `lib/providers/app_provider.dart`：

1. 新增字段：
   - `VisionTrackingService? _visionService`
   - `Map<int, VisionStickFrame> _stickFramesById`
   - `InputMode inputMode`（enum：`imu` / `vision` / `touch`）

2. 在 `_setupListeners()` 中订阅 `frameStream`：

```dart
_visionService!.frameStream.listen(_handleVisionFrame);
```

3. 实现 `_handleVisionFrame(VisionStickFrame frame)`：
   - 更新 `_stickFramesById`
   - 将 `(x, y)` 转为 `Offset(frame.x, frame.y)`
   - 交给 **§13 敲击检测引擎** 处理（不要在这里直接 `_handleStrike`）
   - `_requestStageRefresh(immediate: true)`

4. **输入模式互斥：** `inputMode == vision` 时，跳过 `_handleUdpMessage` 的敲击判定（或保留 IMU 作调试双开，需产品确认）。

### 12.6 步骤 4：ConnectionScreen 增加视觉追踪连接 UI

修改 `lib/screens/connection_screen.dart`：

- 新增 Card「视觉追踪（方案一）」
- TextField：WebSocket 地址，默认 `AppConstants.defaultVisionWsUrl`
- 按钮：连接 / 断开
- 显示：当前 stick 坐标、confidence、可见状态
- 断线时红色提示：「追踪信号丢失」（PRD 要求）

### 12.7 步骤 5：Stage 显示 stick 光标

修改 `lib/widgets/stage_bianzhong_view.dart`：

- 新增 Props：`List<VisionStickFrame> stickFrames`
- 在 `_VirtualHammerPainter` 或新建 `_StickCursorPainter` 绘制 1~2 个光标圆点
- stick `isVisible == false` 时在边缘显示「离屏」标签（PRD 降级模式）

### 12.8 协议规格（与后端对齐）

**服务端 → 客户端（每帧或批量）：**

```json
{
  "type": "stick_frame",
  "timestamp": 1710000000123,
  "stick_id": 1,
  "x": 0.42,
  "y": 0.68,
  "confidence": 0.95,
  "visible": true
}
```

**可选：客户端 → 服务端（调试）：**

```json
{ "type": "strike_ack", "bellId": 25, "stick_id": 1, "timestamp": 1710000000500 }
```

### 12.9 验收标准

- [ ] 连接本地 mock WS 服务器，30Hz 推送坐标，舞台光标平滑移动
- [ ] 断开 WS 后 3s 内自动重连，UI 显示「追踪信号丢失」
- [ ] 单 stick 丢失时显示「离屏」，另一 stick 正常
- [ ] 消息解析延迟 < 5ms（Flutter 侧）

### 12.10 联调 Mock 脚本（便于前端独立开发）

可用 Node/Python 起简易 WS 服务，循环发送：

```json
{"type":"stick_frame","stick_id":1,"x":0.5,"y":0.5,"confidence":0.9,"timestamp":0}
```

x/y 按正弦变化，验证光标运动。

---

## 13. 视觉版敲击检测引擎 — 开发指南

**目标：** 根据 stick 坐标 **历史帧** 判定「悬停」vs「敲击」，输出 `bellId + intensity`。

**不复用** IMU 的 `HammerPoseMapper` / `_resolveGestureStrikeIntensity`，需 **新建独立模块**。

### 13.1 涉及文件（新建）

| 文件 | 职责 |
|------|------|
| `lib/utils/vision_strike_detector.dart` | 核心算法 |
| `lib/models/vision_stick_history.dart` | 每根棒坐标环形缓冲 |

### 13.2 PRD 算法规则（实现依据）

| 规则 | PRD 值 | 代码常量建议 |
|------|--------|--------------|
| 历史帧数 N | 5~8 | `historyLength = 6` |
| 防重敲冷却 | 80ms | `strikeCooldown = 80ms` |
| 最低速度阈值 | ~50 px/帧（待确认） | 归一化坐标下需换算或联调标定 |
| 双棒同时窗口 | ±50ms | `simultaneousWindow = 50ms` |
| 碰撞区 | 比钟面略大 | **复用** `StageHitMapper.hitTestStagePoint` |

> 注意：PRD 用「像素/帧」，前端收到的是 **归一化 0~1**。需在联调时确定换算关系，或在后端直接推送归一化速度。

### 13.3 步骤 1：坐标历史缓冲

```dart
class VisionStickHistory {
  static const int maxLength = 8;
  final List<VisionStickSample> _samples = [];

  void add(Offset point, DateTime time) {
    _samples.add(VisionStickSample(point, time));
    while (_samples.length > maxLength) _samples.removeAt(0);
  }

  double? speedAt(DateTime now) {
    // 最近两帧距离 / dt
  }
}
```

每个 `stickId` 维护一个 `VisionStickHistory` 实例（放在 `AppProvider` 或 `VisionStrikeDetector` 内）。

### 13.4 步骤 2：敲击判定状态机

```dart
enum StickMotionState { idle, hovering, striking }

class VisionStrikeDetector {
  VisionStrikeHitResult? update({
    required int stickId,
    required Offset point,
    required DateTime timestamp,
    required int currentOctave,
  }) {
    // 1. history.add(point, timestamp)
    // 2. hit = StageHitMapper.hitTestStagePoint(currentOctave, point)
    // 3. speed = history.speedAt(timestamp)
    // 4. 若 hit != null && speed 从高于阈值骤降到近零 → strike
    // 5. 检查 cooldown[stickId] 与 cooldown[bellId]
    // 6. 返回 VisionStrikeHitResult(bellId, region, intensity)
  }
}
```

**敲击判定伪逻辑：**

```
IF 当前点在碰撞区内
AND 前一帧速度 > minStrikeSpeed
AND 当前帧速度 < hoverSpeedThreshold  // 骤降
AND 距上次敲同一钟 > 80ms
THEN 触发敲击，intensity = f(峰值速度)
```

### 13.5 步骤 3：接入 AppProvider

在 `_handleVisionFrame` 末尾：

```dart
final hit = _visionStrikeDetector.update(
  stickId: frame.stickId,
  point: Offset(frame.x, frame.y),
  timestamp: frame.timestamp,
  currentOctave: _currentOctave,
);
if (hit != null) {
  _handleStrike(hit.intensity, bellId: hit.bellId, region: hit.region);
}
```

### 13.6 步骤 4：双棒同时敲击

维护 `List<PendingStrike>`，50ms 窗口内收集多 stick 的 strike，一并调用 `_handleStrike`（PRD 和弦场景）。

### 13.7 步骤 5：Settings 调试页（可选）

- 滑块调节 `minStrikeSpeed`、`hoverSpeedThreshold`
- 实时显示每根 stick 当前速度、状态（idle/hovering/striking）
- 写入 `shared_preferences` 持久化

### 13.8 验收标准

- [ ] Mock 数据：快速移入钟区再停止 → 触发 1 次敲击
- [ ] 悬停不触发
- [ ] 同一钟 80ms 内不重复触发
- [ ] 双棒 50ms 内各敲不同钟 → 两音同时响
- [ ] 端到端（WS 收到帧 → 发声）延迟目标 ≤ 150ms

---

## 14. 编钟展示界面增强 — 开发指南

**目标：** 补齐 PRD 3.2.3 中当前舞台尚未完全满足的部分。

### 14.1 待做功能清单

| 功能 | PRD 要求 | 当前 | 开发动作 |
|------|----------|------|----------|
| 半弧形排列 | 半弧形阵列 | 上下两排直线 | 调整 `_bells` x/y 为弧线（可选） |
| 靠近瞄准提示 | 棒子靠近时辅助提示 | 仅有击锤高亮区 | stick 进入钟区附近时显示半透明瞄准圈 |
| 敲击动画 | 200ms 高亮 + 轻微位移 | 300ms 高亮，无位移 | 缩短高亮；`_BianzhongBellPainter` 加 translate 振动 |
| 调试碰撞盒 | 调试模式可见 | 不可见 | 见 §19 |

### 14.2 步骤 1：瞄准提示

`StageBianzhongView` 中，对每个 `stickFrame`：

```dart
final hit = StageHitMapper.hitTestStagePoint(...);
if (hit != null && !isStriking) {
  // 绘制瞄准环：钟周围 dashed circle，颜色随 confidence 变化
}
```

### 14.3 步骤 2：200ms 振动动画

修改 `AppConstants.bellHighlightDuration` 为 `200ms`（或 PRD 专用常量）。

在 `_BianzhongBellPainter` 的 `paint` 中，若 `isActive`：

```dart
final vibration = sin(animationPhase * pi * 4) * 2.0; // 轻微水平位移
canvas.translate(vibration, 0);
```

`animationPhase` 由 `activeBellIds` 进入时启动 200ms AnimationController。

### 14.4 验收标准

- [ ] stick 靠近钟面时出现瞄准提示，离开消失
- [ ] 敲击后 200ms 内完成高亮 + 回弹动画
- [ ] 与视觉敲击检测联调无闪烁

---

## 15. 系统校准向导 — 开发指南

**目标：** 首次启动或摄像头变动时，引导用户 1~2 分钟完成校准（PRD 3.2.6）。

### 15.1 涉及文件（新建）

| 文件 | 职责 |
|------|------|
| `lib/screens/calibration_wizard_screen.dart` | 三步向导主页面 |
| `lib/providers/calibration_provider.dart` | 校准状态（可选，或放 AppProvider） |
| `lib/models/calibration_state.dart` | 步骤枚举、校准结果持久化 |

### 15.2 触发条件

在 `main.dart` 或 `HomeScreen.initState` 中：

```dart
final done = prefs.getBool('calibration_completed') ?? false;
if (!done) {
  Navigator.pushReplacement(context, CalibrationWizardScreen());
}
```

Settings 中增加「重新校准」入口。

### 15.3 三步向导 UI 结构

```
Stepper(currentStep: 0..2)
├── Step 0：摄像头画面确认
│   ├── 说明文字 + 示意图
│   ├── [若后端提供] 摄像头预览占位 / 或文字确认清单
│   └── 按钮「画面正常，下一步」
├── Step 1：标记球识别测试
│   ├── 提示：请挥动左棒 → 检测 stick_id=1 confidence>0.8 持续 2s
│   ├── 提示：请挥动右棒 → stick_id=2 同上
│   ├── 实时显示：左棒 ✓/✗  右棒 ✓/✗
│   └── 两棒均 ✓ 后解锁下一步
└── Step 2：触发映射验证
    ├── 依次高亮 bellId 1..12（或当前八度 12 音）
    ├── 用户用棒敲击对应位置
    ├── 命中则记录；未命中允许「跳过」或「微调」
    └── 完成 → 写入 calibration_completed=true
```

### 15.4 步骤 1 实现细节

订阅 `VisionTrackingService.frameStream`：

```dart
if (frame.stickId == 1 && frame.confidence > 0.8) {
  _leftOkDuration += dt;
  if (_leftOkDuration > 2.seconds) _leftVerified = true;
}
```

UI 用 `Icon(Icons.check_circle)` 变绿。

### 15.5 步骤 2 实现细节

```dart
for (final bellId in bellIdsToVerify) {
  _highlightBellId = bellId;
  await waitForStrikeOnBell(bellId, timeout: 10.seconds);
}
```

可选：将微调偏移写入 `SharedPreferences` 或 `StageHitMapper` 配置（advanced）。

### 15.6 验收标准

- [ ] 首次安装自动进入向导
- [ ] 三步可在 2 分钟内完成
- [ ] 完成后不再自动弹出（除非用户点「重新校准」）
- [ ] 校准中断后可从当前步恢复（可选）

---

## 16. 演示模式控制 — 开发指南

**目标：** 待机 attract loop ↔ 演奏模式自动切换（PRD 3.2.7）。

### 16.1 涉及文件

| 文件 | 职责 |
|------|------|
| `lib/models/app_demo_mode.dart` | enum `DemoMode { standby, performing }` |
| `lib/screens/standby_screen.dart` | Attract loop 全屏页（或 HomeScreen 内切换） |
| `lib/providers/app_provider.dart` | 模式状态、超时 Timer |

### 16.2 状态机

```
standby（待机）
  │ 条件：stick 进入交互区域（x,y 在中心 70% 内且 visible）
  │ 或：用户点击「开始体验」
  ▼
performing（演奏）
  │ 条件：60s 内无任何有效敲击
  ▼
standby
```

### 16.3 步骤 1：AppProvider 增加演示模式

```dart
DemoMode _demoMode = DemoMode.standby;
DateTime? _lastStrikeAt;

void _onAnyStrike() {
  _lastStrikeAt = DateTime.now();
  if (_demoMode == DemoMode.standby) enterPerformingMode();
}

Timer.periodic(1s, (_) {
  if (_demoMode == DemoMode.performing &&
      _lastStrikeAt != null &&
      DateTime.now().difference(_lastStrikeAt!) > Duration(seconds: 60)) {
    enterStandbyMode();
  }
});
```

### 16.4 步骤 2：Standby 页面

`standby_screen.dart` 内容建议：

- 全屏深色背景 + 编钟文化简介文案（轮播 3~5 条）
- 轻量动画：编钟剪影缓慢旋转 / 粒子效果（可用现有 CustomPaint）
- 底部：「触摸屏幕开始」或等待 stick 进入

### 16.5 步骤 3：与 HomeScreen 关系

**方案 A（推荐）：** `MaterialApp.home` 改为 `DemoModeRouter`，根据 `_demoMode` 切换 `StandbyScreen` / `HomeScreen`。

**方案 B：** HomeScreen 上层 `Stack`，standby 时覆盖全屏 Overlay。

### 16.6 步骤 4：演奏模式控制按钮（可选）

Settings 或展厅隐藏手势：

- 开始 / 暂停 / 重置
- 重置 = 停止所有音频 + 回 standby + 清状态

### 16.7 验收标准

- [ ] 启动默认 standby（可配置展览模式开关）
- [ ] stick 进入交互区 → 自动切 performing
- [ ] 60s 无敲击 → 回 standby
- [ ] 切换过程无 crash，音频正确 stop

---

## 17. 音频高级能力 — 开发指南

**目标：** 满足 PRD 3.2.4 多音混音策略。

### 17.1 当前局限

`AudioService` 仅 `player.play()` + 音量 × intensity，无全局活跃实例计数、无 DRC。

### 17.2 步骤 1：活跃实例追踪

```dart
class ActiveVoice {
  final int bellId;
  final DateTime startedAt;
  final AudioPlayer player;
}
final List<ActiveVoice> _activeVoices = [];
```

每次 `playBell` 加入列表；`onPlayerComplete` 移除。

### 17.3 步骤 2：多音 3dB 衰减

```dart
int n = _activeVoices.length + 1;
final gainCompensation = pow(10, -3 * (n - 1) / 20); // 每增 1 音 -3dB
final adjustedVolume = _volume * intensity * gainCompensation;
```

### 17.4 步骤 3：DRC（简化版）

当 `_activeVoices.length >= 3`：

```dart
final masterGain = (1.0 / sqrt(n)).clamp(0.3, 1.0);
```

或使用 `audioplayers` 无法实现真正 DRC 时，文档注明 **需原生音频引擎**（如 `flutter_soloud`）作为后续升级。

### 17.5 步骤 4：混响（三音以上）

PRD 要求三音以上加轻度混响。Flutter 纯 `audioplayers` **不支持** 实时混响。

**可选路径：**

| 路径 | 工作量 | 说明 |
|------|--------|------|
| A. 预渲染带混响采样 | 低 | 美术/音频同学导出两套 WAV |
| B. 换 `flutter_soloud` / 原生插件 | 高 | 真混响 |
| C. 双播放器叠加延迟副本模拟 | 中 | 伪混响，效果有限 |

建议阶段一用 **路径 A**；文档标注 B 为 v2。

### 17.6 步骤 5：补全音频资源

1. 从原项目或录音团队获取 `bell_*.wav`
2. 放入 `assets/audio/`
3. 对照 `BellMapping.availableAssets` 核对文件名
4. `flutter pub get` 后 Settings → 测试所有编钟

### 17.7 验收标准

- [ ] 单音响度正常
- [ ] 双音同时无明显削波
- [ ] 四音同时总响度低于单音（3dB 补偿可听感验证）
- [ ] 所有 bellId 有对应可播放文件

---

## 18. 现状补齐项 — 开发指南

以下代码 **已有**，按步骤集成即可。

### 18.1 集成 BleProvisionSheet（蓝牙配网）

**文件：** `lib/widgets/ble_provision_sheet.dart` → `connection_screen.dart`

**步骤：**

1. 在 `ConnectionScreen` 增加「蓝牙配网」`ListTile` 或按钮
2. `onTap: () => showModalBottomSheet(context, builder: (_) => BleProvisionSheet())`
3. 桌面端点击时 SnackBar 提示：「请使用手机 App 完成配网」（`BleProvisioningService` 已有限制）
4. 移动端走完整扫描 → 选 WiFi → 下发流程

**验收：** Android 真机可扫描 `BianzongHammer-*` 并完成配网。

### 18.2 统一 FollowAlongScreen 导航

**现状：** `FollowAlongScreen` 完整但未使用；Home 用弹窗选曲。

**方案 A — 改用独立页（推荐）：**

1. `_FollowAlongButton.onTap` 改为 `Navigator.push(FollowAlongScreen())`
2. 删除 Home 内 `_showSongSelectionDialog` 与简化版 `_FollowAlongOverlay`
3. `FollowAlongScreen` 内选曲 → `provider.startFollowAlong` → 留在本页看进度/结果

**方案 B — 删除 FollowAlongScreen：**

1. 删除 `follow_along_screen.dart`
2. 保留 Home 弹窗 + Overlay

**验收：** 跟奏全流程只保留 **一条** UI 路径，无重复。

### 18.3 集成 ConnectionStatusWidget

1. `HomeScreen` AppBar `actions` 前插入 `ConnectionStatusWidget()`
2. 或 `SettingsScreen` 顶部固定显示
3. 组件内 `Consumer<AppProvider>` 读 `connectionStatus.displayName` + 颜色圆点

### 18.4 处理 BellGridWidget

- **调试用途：** Settings 增加「开发者选项」→ 进入含 `BellGridWidget` 的页面
- **或删除：** 确认无引用后 `git rm bell_grid_widget.dart`

### 18.5 生成 Android/iOS 平台工程

```bash
cd bianzhong_ninja_copy
flutter create . --platforms=android,ios
flutter pub get
```

注意检查 `android/app/src/main/AndroidManifest.xml` 蓝牙/WiFi 权限。

### 18.6 抽取 StageLayoutConfig（消除双份配置）

**问题：** `stage_bianzhong_view.dart` 与 `stage_hit_mapper.dart` 各有一份钟位置。

**步骤：**

1. 新建 `lib/utils/stage_layout_config.dart`：

```dart
class StageBellLayout {
  final String note;
  final double x, y;
  final bool isUpper;
  final double visualScale;
  static const List<StageBellLayout> bells = [ ... ];
}
```

2. `StageBianzhongView` 与 `StageHitMapper` **均 import 此文件**
3. 删除两处重复常量
4. 改布局只改一处

**验收：** 改一个 x 值，视觉与碰撞同步变化。

---

## 19. Debug 碰撞盒可视化 — 开发指南

**目标：** PRD 要求调试模式下叠加显示隐性碰撞盒。

### 19.1 步骤

1. `AppProvider` 增加 `bool debugShowHitBoxes`（Settings 开关）
2. `StageBianzhongView` 增加 Prop：`debugShowHitBoxes`
3. 新建 `_DebugHitBoxPainter`：
   - 遍历 `StageHitMapper` 暴露的 layout（需在 mapper 增加 `static List<StageStrikeLayout> layoutsForOctave(int)`）
   - 绘制 left/center/right 三个 rect，半透明红/绿/蓝
4. `Stack` 最上层 `CustomPaint(painter: _DebugHitBoxPainter)`

### 19.2 验收

- [ ] Settings 打开「显示碰撞盒」后立即可见
- [ ] 与鼠标点击命中区域一致

---

## 20. 输入模式切换（IMU / 视觉并存）

若产品要求 **保留 IMU 击锤** 同时支持 **视觉方案**：

### 20.1 AppProvider 增加 InputMode

```dart
enum InputMode { imu, vision, touchOnly }

InputMode _inputMode = InputMode.imu;
```

### 20.2 ConnectionScreen 增加模式选择

- 单选：IMU 击锤（UDP） / 视觉追踪（WS） / 仅触控（调试）
- 切换时 `disconnect()` 旧服务，连接新服务

### 20.3 数据处理分支

```dart
void _routeInput() {
  switch (_inputMode) {
    case InputMode.imu:      // 现有 _handleUdpMessage
    case InputMode.vision:   // _handleVisionFrame + VisionStrikeDetector
    case InputMode.touchOnly: // 仅 Stage onBellTapped
  }
}
```

---

## 21. 开发路线图（含工时估算）

| 阶段 | 内容 | 章节 | 预估 |
|------|------|------|------|
| **一** | 音频资源 + UI 集成 + StageLayoutConfig | §17.6、§18 | 3~5 天 |
| **二** | VisionTrackingService + Mock 联调 | §12 | 3~5 天 |
| **三** | VisionStrikeDetector + 舞台增强 | §13、§14 | 5~7 天 |
| **四** | 校准向导 | §15 | 3~4 天 |
| **五** | 演示模式 | §16 | 2~3 天 |
| **六** | 音频 DRC + Debug 碰撞盒 | §17、§19 | 3~5 天 |
| **联调** | 与 Python 追踪端到端 + 150ms 延迟测试 | 全程 | 3~5 天 |

**合计约 4~6 周**（1 名 Flutter 前端 + 1 名算法/后端并行）。

---

## 22. 各模块验收 Checklist（汇总）

### 视觉追踪链路

- [ ] WS 连接/重连/丢失提示
- [ ] 双 stick 光标与离屏降级
- [ ] 敲击判定准确率（人工测试 20 次）
- [ ] 端到端延迟 ≤ 150ms

### 展厅体验

- [ ] 校准向导 2 分钟内可完成
- [ ] 待机 60s 超时回 attract
- [ ] stick 进入自动开始

### 音频

- [ ] 全部 bellId 可播放
- [ ] 多音无削波

### 工程健康

- [ ] Stage 布局单点配置
- [ ] 无未引用死代码（或移入 debug 页）
- [ ] IMU/视觉模式可切换（若需要）

---

## 23. 附录

### 23.1 AppConstants 速查

| 常量 | 值 |
|------|-----|
| defaultUdpPort | 3333 |
| defaultWsUrl | ws://192.168.4.1:81 |
| bellCount | 60 |
| defaultOctave | 3 |
| maxHammerCount | 12 |
| uiStrikeDebounce | 180ms |
| bellHighlightDuration | 300ms |

### 23.2 bellId 速查（八度 3）

| 音名 | bellId | 音名 | bellId |
|------|--------|------|--------|
| C3 | 25 | F3 | 30 |
| D3 | 27 | G3 | 32 |
| E3 | 29 | A3 | 34 |
| B3 | 36 | | |

---

*文档维护：第一部分变更请同步更新第 5~10 章；第二部分待办完成后再移入第一部分。*
