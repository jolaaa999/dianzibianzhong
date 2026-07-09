# 虚拟数字编钟 — 项目接手说明

> 文档目的：帮助新接手的前端/客户端开发者快速理解当前代码库，并为后续编写《前端开发文档》提供结构化参考。
>
> 基于源码目录 `bianzhong_ninja_copy/` 与 PRD `electronic-bianzhong-prd-v1(1).docx` 整理。  
> 整理日期：2026-07-09

---

## 1. 项目一句话概括

**虚拟数字编钟** 是一套面向展厅/演示场景的交互式音乐应用：用户通过 **ESP32 智能击锤（IMU 姿态传感）** 或 **屏幕触控/鼠标** 触发虚拟编钟，应用实时播放编钟采样音并给出视觉反馈。当前客户端为 **Flutter 多平台应用**（Windows / Android / iOS），而非 PRD 中规划的纯 Web 前端。

---

## 2. PRD 与当前实现的差异（必读）

接手时最容易混淆的是：**PRD 描述的是「视觉追踪方案」，而现有源码实现的是「IMU 击锤 + UDP 广播方案」**。

| 维度 | PRD（方案一：视觉追踪） | 当前源码（`bianzhong_ninja_copy`） |
|------|-------------------------|-------------------------------------|
| 输入硬件 | USB 摄像头 + 反光标记敲击棒 | ESP32-S3 击锤 + BNO085 IMU |
| 定位方式 | OpenCV 识别 XY 坐标 | 四元数/欧拉角 → 舞台坐标映射 |
| 后端进程 | Python 视觉追踪模块 | 击锤固件 UDP 广播 JSON |
| 通信协议 | WebSocket（stick_id, x, y） | **主路径：UDP 3333**；兼容 WebSocket |
| 客户端形态 | 浏览器 / Electron | **Flutter 桌面 + 移动端** |
| 编钟数量 | PRD 建议 8~12 个 | 舞台展示 **12 个钟面**（7 下 + 5 上），音域 **60 个 bellId**（5 八度 × 12 音） |
| 特色模式 | 校准向导、待机/演奏模式 | **水果忍者模式**、**智能跟奏模式**、蓝牙配网 |
| 多音复音 | PRD 强调和弦混音 | 16 路 AudioPlayer 声部池，可叠加播放 |

**结论：**

- 现有 Flutter 工程是 **可运行的 IMU 击锤交互客户端**，包含大量可直接复用的 UI/音频/状态管理代码。
- PRD 是 **下一版展厅方案** 的产品需求；若按 PRD 做视觉追踪，需要新增 Python 追踪服务，并重构输入层（坐标驱动替代姿态驱动），但 **编钟展示、敲击检测、音频播放、动画反馈** 等前端模块仍可借鉴。

---

## 3. 技术栈

| 类别 | 选型 | 说明 |
|------|------|------|
| 框架 | Flutter 3.x（Dart SDK ^3.11.5） | 包名 `bianzhong_app` |
| 状态管理 | `provider` | 全局 `AppProvider`（ChangeNotifier） |
| 音频 | `audioplayers` | 16 路播放器池，支持多音叠加 |
| 网络 | `web_socket_channel`、`dart:io` UDP | 硬件输入 + 旧版兼容 |
| 蓝牙配网 | `esp_blufi_for_flutter`（本地 third_party） | 手机端 BluFi 给击锤配 WiFi |
| 本地存储 | `shared_preferences` | 配置持久化（当前使用较少） |
| UI | Material 3 | 琥珀色主题，支持亮/暗/跟随系统 |

---

## 4. 系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     Flutter 客户端 (bianzhong_app)               │
├─────────────────────────────────────────────────────────────────┤
│  Screens          │  HomeScreen / SettingsScreen /               │
│                   │  ConnectionScreen / FollowAlongScreen          │
├───────────────────┼──────────────────────────────────────────────┤
│  Widgets          │  StageBianzhongView（核心舞台）               │
│                   │  BellGridWidget / BleProvisionSheet          │
├───────────────────┼──────────────────────────────────────────────┤
│  State            │  AppProvider（业务中枢）                        │
├───────────────────┼──────────────────────────────────────────────┤
│  Services         │  UdpHammerService / WebSocketService         │
│                   │  AudioService / BleProvisioningService       │
│                   │  WifiInfoService                             │
├───────────────────┼──────────────────────────────────────────────┤
│  Utils            │  HammerPoseMapper / StageHitMapper           │
│                   │  SlashDetector / BladeTrail / constants      │
└───────────────────┴──────────────────────────────────────────────┘
         ▲ UDP :3333 JSON              ▲ WebSocket (兼容)
         │                              │
┌────────┴────────┐            ┌───────┴────────┐
│ ESP32 智能击锤   │            │ 旧版 AP 固件    │
│ (IMU + WiFi)    │            │ ws://192.168.4.1:81 │
└─────────────────┘            └─────────────────┘
```

### 4.1 核心数据流（UDP 主路径）

1. 应用启动 → `AppProvider` 构造函数自动调用 `startHardwareDiscovery()`，监听 UDP 3333。
2. 击锤广播 JSON → `UdpHammerService` 解析为 `UdpHammerMessage`。
3. `AppProvider._handleUdpMessage()`：
   - `HammerPoseMapper`：四元数/欧拉角 → 舞台归一化坐标 (stageX, stageY)。
   - `StageHitMapper`：坐标碰撞检测 → `bellId` + 敲击区域（左/中/右）。
   - 判定有效敲击 → `AudioService.playBell()` + 更新 `_bellStates` 高亮。
4. `StageBianzhongView` 通过 `stageRevisionListenable` 以 ~33ms 节奏刷新舞台。

---

## 5. 目录结构

```
dianzibianzhong/
├── 6a4e4d78..._electronic-bianzhong-prd-v1(1).docx   # 产品需求文档
├── PROJECT_OVERVIEW.md                                # 本文档
└── bianzhong_ninja_copy/                              # Flutter 工程根目录
    ├── pubspec.yaml
    ├── lib/
    │   ├── main.dart                    # 入口，MaterialApp + Provider
    │   ├── providers/
    │   │   └── app_provider.dart        # ★ 全局状态与业务逻辑
    │   ├── screens/
    │   │   ├── home_screen.dart         # ★ 主演奏页
    │   │   ├── settings_screen.dart     # 设置
    │   │   ├── connection_screen.dart   # UDP / WebSocket 连接
    │   │   └── follow_along_screen.dart # 跟奏（独立页，主入口在 Home）
    │   ├── widgets/
    │   │   ├── stage_bianzhong_view.dart  # ★ 编钟舞台（CustomPaint）
    │   │   ├── bell_grid_widget.dart      # 网格选钟（备用 UI）
    │   │   ├── ble_provision_sheet.dart   # 蓝牙配网底部弹层
    │   │   └── connection_status_widget.dart
    │   ├── services/
    │   │   ├── udp_hammer_service.dart    # ★ UDP 硬件输入
    │   │   ├── websocket_service.dart     # 旧版 WebSocket
    │   │   ├── audio_service.dart         # ★ 音频播放
    │   │   ├── ble_provisioning_service.dart
    │   │   └── wifi_info_service.dart
    │   ├── models/
    │   │   ├── sensor_data.dart           # 传感器 / WebSocket 消息模型
    │   │   ├── song_model.dart            # 跟奏数据模型
    │   │   └── song_library.dart          # 曲库（目前仅「小星星」）
    │   └── utils/
    │       ├── constants.dart             # ★ 常量、BellMapping、音源映射
    │       ├── hammer_pose_mapper.dart    # 击锤姿态 → 光标
    │       ├── stage_hit_mapper.dart      # 坐标 → 编钟碰撞
    │       ├── slash_detector.dart        # 忍者模式挥砍检测
    │       └── blade_trail.dart           # 刀光轨迹
    ├── assets/
    │   ├── audio/                         # bell_*.wav 采样（pubspec 已声明）
    │   └── images/
    └── third_party_esp_blufi_for_flutter/ # 蓝牙配网插件
```

---

## 6. 页面与交互说明

### 6.1 HomeScreen（主界面）

路径：`lib/screens/home_screen.dart`

- **AppBar 左侧**：模式切换 Chip
  - **水果忍者**：开启 `ninjaMode`，挥砍轨迹触发多钟连击。
  - **智能跟奏**：选曲后倒计时 3 秒，按节拍高亮目标钟，统计命中/未中。
- **AppBar 右侧**：设置、关闭应用。
- **主体**：`StageBianzhongView` 全屏编钟舞台。
- **跟奏倒计时**：顶部半透明 Overlay。

> 注意：`FollowAlongScreen` 已实现完整跟奏 UI（进度条、暂停/停止、结果页），但当前主入口在 HomeScreen 的弹窗选曲，未导航到独立页面。

### 6.2 SettingsScreen（设置）

路径：`lib/screens/settings_screen.dart`

| 区块 | 功能 |
|------|------|
| 音频设置 | 开关、音量滑块 |
| 传感器设置 | 灵敏度（影响敲击强度映射） |
| 配网与连接 | 跳转 ConnectionScreen |
| 测试功能 | WebSocket 测试消息、依次播放 60 个钟 |

### 6.3 ConnectionScreen（连接管理）

路径：`lib/screens/connection_screen.dart`

- **推荐方式**：UDP 3333 监听（同局域网接收击锤广播）。
- **兼容方式**：WebSocket `ws://192.168.4.1:81`（旧 AP 固件）。
- 默认 WiFi：`Bianzong_Stage` / 密码 `12345678`。

### 6.4 StageBianzhongView（核心 UI 组件）

路径：`lib/widgets/stage_bianzhong_view.dart`（约 1300+ 行）

这是前端开发文档应重点描述的组件，职责包括：

1. **编钟渲染**：CustomPainter 绘制钟架、上下两排共 12 个钟面、编钟纹饰。
2. **交互输入**：
   - 鼠标/触控：`Listener` 处理 pointer down/move/up。
   - 硬件击锤：读取 `hammerSensorStates` 显示光标/瞄准区域。
3. **敲击区域**：每个钟分左/中/右三个隐性碰撞区（侧击会转调）。
4. **视觉反馈**：
   - `activeBellIds` → 高亮着色。
   - 跟奏模式 `followAlongNotePulse` → 200ms 闪光。
   - 击锤动画 `_strikeController` 模拟下砸。
5. **忍者模式**：绘制 `BladeTrail` 刀光轨迹，线段与钟碰撞触发发声。

**舞台钟面布局（当前八度下的 12 个音）：**

| 上层（5 钟） | C# | D# | F# | G# | A# |
|-------------|----|----|----|----|-----|
| 下层（7 钟） | C | D | E | F | G | A | B |

每个钟在舞台上的 x 位置由 `StageBellConfig` 定义（归一化 0~1），与 `StageHitMapper` 中的布局配置需保持一致。

---

## 7. 状态管理：AppProvider

路径：`lib/providers/app_provider.dart`

`AppProvider` 是整个应用的 **唯一业务中枢**，前端文档建议以其为中心描述状态字段与事件。

### 7.1 连接相关

| 字段/方法 | 说明 |
|-----------|------|
| `connectionStatus` | disconnected / listening / connecting / connected / reconnecting / error |
| `startHardwareDiscovery()` | 启动 UDP 监听（构造时自动调用） |
| `connectLegacyWebSocket(url)` | 连接旧版 WebSocket |
| `activeHammers` | 当前在线击锤列表（最多 12 个） |
| `scanBleProvisionDevices()` | 扫描 `BianzongHammer-*` 蓝牙设备 |
| `provisionBleDevice()` | BluFi 下发 WiFi（**仅 Android/iOS**） |

### 7.2 演奏相关

| 字段/方法 | 说明 |
|-----------|------|
| `currentOctave` | 当前八度（1~5，默认 3） |
| `onBellTapped(bellId, intensity, region)` | 屏幕/鼠标敲击入口 |
| `activeBellIds` | 正在高亮的钟 ID 集合 |
| `volume` / `sensitivity` / `audioEnabled` | 音频与传感器参数 |

### 7.3 模式相关

| 模式 | 开关 | 核心逻辑 |
|------|------|----------|
| 普通演奏 | 默认 | UDP/触控 → 单点碰撞 → 发声 |
| 水果忍者 | `ninjaMode = true` | 高速挥砍 → 轨迹段碰撞 → 多钟连击 |
| 智能跟奏 | `startFollowAlong(songId)` | 定时推进音符 → 比对 `bellId` → 统计 hit/miss |

### 7.4 UI 刷新机制

- Provider 的 `notifyListeners()` 驱动 Settings 等普通 Widget。
- 舞台使用 `ValueNotifier<int> stageRevision` + `ValueListenableBuilder`，避免全树重建，目标刷新间隔约 33ms（`AppConstants.stageRefreshInterval`）。

---

## 8. 硬件通信协议

### 8.1 UDP 击锤消息（主协议）

- **端口**：`3333`（`AppConstants.defaultUdpPort`）
- **格式**：UTF-8 JSON，单条 datagram

```json
{
  "type": "strike",
  "id": 1,
  "deviceId": "esp32-abc123",
  "octave": 3,
  "yaw": 12.5,
  "pitch": -8.2,
  "roll": 1.0,
  "quaternion": { "w": 0.99, "x": 0.01, "y": 0.05, "z": 0.02 },
  "force": 0.75,
  "timestamp": 1710000000123456
}
```

| 字段 | 说明 |
|------|------|
| `type` | `"strike"` 表示敲击事件；其他类型可传姿态心跳 |
| `id` | 击锤编号 1~12 |
| `deviceId` | 设备唯一标识，缺省则用来源 IP |
| `octave` | 可选，指定当前八度 |
| `force` | 敲击强度 0~1 |
| `timestamp` | 微秒时间戳 |

**活跃击锤管理**：3 秒无数据则剔除（`AppConstants.hammerTimeout`）。

### 8.2 WebSocket 消息（兼容协议）

路径：`lib/models/sensor_data.dart` → `WebSocketMessage`

| type | 方向 | 说明 |
|------|------|------|
| `sensor` | 服务端 → 客户端 | 传感器数据，含 quaternion、strike、intensity |
| `touch` | 客户端 → 服务端 | 屏幕敲击 `{ bellId, intensity }` |
| `haptic` | 客户端 → 服务端 | 触觉反馈请求 |
| `ping` / `pong` / `heartbeat` / `welcome` | 双向 | 保活 |

默认地址：`ws://192.168.4.1:81`

### 8.3 若对接 PRD 视觉追踪协议（待实现）

PRD 建议的消息结构：

```json
{
  "timestamp": 1710000000,
  "stick_id": 1,
  "x": 0.42,
  "y": 0.68,
  "confidence": 0.95
}
```

对接时可新增 `VisionTrackingService`，将 (x, y) 直接送入 `StageHitMapper.hitTestStagePoint()`，复用现有音频与 UI 反馈链路。

---

## 9. 编钟音域与音频系统

### 9.1 BellMapping（60 钟模型）

路径：`lib/utils/constants.dart`

- **bellId 范围**：1 ~ 60
- **计算公式**：`(octave - 1) * 12 + noteIndex + 1`
- **音名顺序**：C, C#, D, D#, E, F, F#, G, A#, A, A#, B

### 9.2 侧击转调规则

`StageStrikeRegion.left / right` 敲击时，实际播放音高会通过 `BellMapping.nextTwoScaleStepsBellId()` 跳两个音阶（模拟编钟侧击泛音效果）。

### 9.3 音频资源

- 路径：`assets/audio/bell_*.wav`
- 映射：`BellMapping.resolveAssetFileName()` 按 note + octave 匹配最近可用采样。
- 多音：16 个 `AudioPlayer` 轮询播放，强度 = `volume × intensity`。

---

## 10. 关键算法模块

### 10.1 HammerPoseMapper（姿态 → 光标）

- 将击锤 IMU 数据当作「空中鼠标」：相对旋转增量驱动 cursor 移动。
- 输出 `displayPoint`（显示用）和 `strikePoint`（碰撞检测用）。
- 含 dead zone、速度自适应滤波，抑制手抖。

### 10.2 StageHitMapper（坐标 → 编钟）

- 每个钟有 shell 路径 + 左/中/右三个 hit rect。
- 支持单点 `hitTestStagePoint()` 和轨迹 `hitTestTrailSegments()`（忍者模式）。
- **调试建议**：PRD 要求「调试模式显示碰撞盒」，当前代码碰撞区不可见，可在 Stage 上叠加 debug 层。

### 10.3 敲击判定（AppProvider）

普通模式接受敲击需满足：

- UDP 消息 `type == strike` 或手势推断敲击；
- 坐标落在有效碰撞区；
- `force × sensitivity >= 0.12`；
- 180ms 防抖（`uiStrikeDebounce`）。

手势敲击（`_resolveGestureStrikeIntensity`）额外检测角速度、下砸速度、锁定时间。

---

## 11. 特色功能详解

### 11.1 水果忍者模式

| 组件 | 作用 |
|------|------|
| `SlashState` | 根据角速度判定是否处于挥砍状态 |
| `BladeTrail` | 记录最近 24 个轨迹点，350ms 渐隐 |
| `StageHitMapper.hitTestTrailSegments` | 轨迹线段与钟碰撞 |

开启忍者模式会自动关闭跟奏；鼠标拖曳也可产生刀光（桌面端）。

### 11.2 智能跟奏模式

- 曲库：`SongLibrary.songs`（当前仅「小星星」）。
- 流程：选曲 → 3 秒倒计时 → 按 BPM 推进音符 → 高亮当前钟 → 用户敲击匹配 → 结束统计准确率。
- 数据模型：`Song` / `SongNote` / `FollowAlongProgress`。

---

## 12. 平台差异与部署

| 平台 | 支持情况 | 备注 |
|------|----------|------|
| Windows | ✅ 主要目标 | 可 UDP 监听；蓝牙配网不可用 |
| Android / iOS | ✅ | 支持 BluFi 蓝牙配网 |
| Linux | 部分 | WiFi 扫描依赖 nmcli |
| Web | ❌ | UDP/BLE 不可用 |

### 本地运行

```bash
cd bianzhong_ninja_copy
flutter pub get
flutter run -d windows   # 或其他设备
```

### 网络前置条件

1. 击锤与客户端在同一 WiFi（默认 `Bianzong_Stage`）。
2. 防火墙放行 UDP 3333 入站。
3. 首次使用击锤需通过 App 蓝牙配网（手机端）。

---

## 13. 与 PRD 功能对照表

| PRD 模块 | 当前实现状态 | 说明 |
|----------|--------------|------|
| 视觉追踪系统 | ❌ 未实现 | 需 Python + OpenCV 新服务 |
| 敲击检测引擎 | ⚠️ 部分实现 | IMU/手势/轨迹检测已有；非像素速度模型 |
| 编钟展示界面 | ✅ 已实现 | `StageBianzhongView`，12 钟面 + 动画 |
| 声音合成引擎 | ✅ 已实现 | 采样播放 + 16 复音；无 DRC/混响 |
| 通信中间件 | ⚠️ 部分实现 | UDP + WebSocket；无 PRD stick 协议 |
| 系统校准向导 | ❌ 未实现 | 可新增引导页 |
| 演示模式控制 | ❌ 未实现 | 无待机/attract loop |
| 多棒同时敲击 | ✅ 已实现 | 最多 12 击锤 + 16 音频实例 |
| 端到端延迟 ≤150ms | ⚠️ 待测 | 取决于网络与设备 |

---

## 14. 编写《前端开发文档》的建议大纲

基于当前代码，建议你的前端开发文档按以下结构展开：

1. **产品背景与目标用户**（引用 PRD 第 1、2 章）
2. **终端形态与部署架构**（Flutter 多平台 + 后续 Web/Electron 规划）
3. **信息架构 & 页面路由**
   - Home / Settings / Connection / FollowAlong
4. **设计规范**
   - Material 3 主题色（amber seed）
   - 舞台尺寸自适应（`LayoutBuilder`，960px / 760px 断点）
5. **核心组件规格书**
   - `StageBianzhongView`：Props 列表、坐标系、碰撞模型、动画时序
   - `BellGridWidget`：八度选择器（若保留）
6. **状态机文档**
   - `ConnectionStatus` 状态图
   - `FollowAlongState` 状态图
   - `ninjaMode` 与普通模式互斥规则
7. **硬件接口契约**
   - UDP JSON Schema
   - WebSocket Message Schema
   - （规划）Vision Tracking Schema
8. **音频规范**
   - bellId ↔ 音名 ↔ 资源文件映射表
   - 侧击转调规则
9. **交互时序图**
   - 击锤敲击 → 发声 → 高亮 时序
   - 跟奏模式音符推进时序
10. **待开发项 Backlog**（对齐 PRD）
    - 视觉追踪接入层
    - 校准向导 UI
    - 待机/演奏模式
    - 调试模式碰撞盒可视化
    - 音频 DRC / 混响

---

## 15. 已知注意点 / 技术债

1. **PRD 与代码输入方案不一致**：接手后应先与产品确认以哪条路线为准。
2. **`FollowAlongScreen` 未被主导航使用**：跟奏 UI 存在两套（Home Overlay vs 独立页）。
3. **`BellGridWidget` 未被 HomeScreen 引用**：可能是早期 UI，现以 Stage 为主。
4. **桌面端蓝牙配网不可用**：ConnectionScreen 未集成 `BleProvisionSheet`，需在 Settings/Connection 流程确认入口。
5. **assets 目录**：pubspec 声明了 audio/images，若本地缺失需补资源否则音频 fallback 到 `bell_c3.wav`。
6. **碰撞布局双份配置**：`StageBianzhongView._bells` 与 `StageHitMapper._bells` 坐标需手动同步，改 UI 时容易遗漏。

---

## 16. 快速定位指南

| 我想改… | 看哪个文件 |
|---------|------------|
| 主界面布局/模式按钮 | `lib/screens/home_screen.dart` |
| 编钟外观/动画/触控 | `lib/widgets/stage_bianzhong_view.dart` |
| 击锤坐标映射 | `lib/utils/hammer_pose_mapper.dart` |
| 碰撞检测区域 | `lib/utils/stage_hit_mapper.dart` |
| 敲击是否生效 | `lib/providers/app_provider.dart` → `_handleUdpMessage` |
| 音频/音量 | `lib/services/audio_service.dart` |
| 音名/八度/bellId | `lib/utils/constants.dart` → `BellMapping` |
| UDP 协议 | `lib/services/udp_hammer_service.dart` |
| 跟奏曲谱 | `lib/models/song_library.dart` |
| 连接/配网 UI | `lib/screens/connection_screen.dart` |
| 全局常量/阈值 | `lib/utils/constants.dart` → `AppConstants` |

---

## 17. 相关文档

- 产品需求：`6a4e4d78e88f1c6adcf0dad4_electronic-bianzhong-prd-v1(1).docx`
- Flutter 依赖：`bianzhong_ninja_copy/pubspec.yaml`
- 蓝牙配网插件：`bianzhong_ninja_copy/third_party_esp_blufi_for_flutter/README.md`

---

*如有疑问，建议优先阅读 `AppProvider` 与 `StageBianzhongView`，这两个文件覆盖了 80% 的业务与 UI 逻辑。*
