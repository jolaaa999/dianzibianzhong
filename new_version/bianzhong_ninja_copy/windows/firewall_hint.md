# Windows 防火墙放行 UDP 3333

数字编钟击锤系统使用 UDP `:3333` 进行击锤 ↔ 应用通信。
首次在 Windows 上以桌面模式运行时，Windows Defender 防火墙可能会拦截入站 UDP，
导致桌面端虽然启动但**收不到任何击锤数据**。

## 现象
- 桌面 App 启动 OK，UDP 状态显示「正在监听」。
- 击锤上电并连接路由器后，桌面「活跃击锤」列表始终为空。

## 解决方案（两种择一）

### 方案 A：首次运行时点「允许」
首次运行 Flutter 桌面时，Windows 会弹防火墙询问；只要点 **允许访问** 即可。

### 方案 B：以管理员权限执行以下命令（一次性手动放行）

```powershell
netsh advfirewall firewall add rule name="BianzhongHammer UDP 3333" dir=in action=allow protocol=UDP localport=3333
```

完成后可用：

```powershell
netsh advfirewall firewall show rule name="BianzhongHammer UDP 3333"
```

确认规则已生效。

## 现场快速诊断顺序
1. **路由器**：在路由管理界面关闭 AP isolation / 客户端隔离，确保 2.4GHz 与 5GHz 同 SSID。
2. **击锤端**：从击锤串口日志确认 `cursor_pkts` 在持续增长（≥1700/分钟）。
3. **桌面端**：从「设置 → 重启 UDP」按钮调用 `_udpService.restart()`。
4. **防火墙**：执行上面命令放行。
5. **Mock**：使用 `flutter run -d windows --dart-define=MOCK=swinger` 在无硬件时也能看到 cursor / strike。
