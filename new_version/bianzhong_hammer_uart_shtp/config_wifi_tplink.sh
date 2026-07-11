#!/bin/bash
# 快速配置ESP32 WiFi - TP-LINK_1858

PORT=${1:-/dev/ttyUSB0}
SSID="TP-LINK_1858"
PASSWORD="1234567890"
HAMMER_ID=${2:-0}

echo "=========================================="
echo "  ESP32 WiFi配置"
echo "=========================================="
echo ""
echo "串口: $PORT"
echo "WiFi SSID: $SSID"
echo "WiFi密码: $PASSWORD"
echo "击锤ID: $HAMMER_ID"
echo ""

# 检查串口
if [ ! -e "$PORT" ]; then
    echo "错误: 串口 $PORT 不存在"
    echo ""
    echo "可用串口:"
    ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  未找到串口设备"
    exit 1
fi

# 配置串口
stty -F $PORT 115200 cs8 -cstopb -parenb raw

echo "发送配置命令..."
echo ""

# 发送配置命令
echo "config_wifi_ssid $SSID" > $PORT
sleep 0.3
echo "✓ SSID已设置"

echo "config_wifi_pass $PASSWORD" > $PORT
sleep 0.3
echo "✓ 密码已设置"

echo "config_hammer_id $HAMMER_ID" > $PORT
sleep 0.3
echo "✓ 击锤ID已设置"

echo "save_config" > $PORT
sleep 0.5
echo "✓ 配置已保存到NVS"

echo ""
echo "=========================================="
echo "  配置完成！"
echo "=========================================="
echo ""
echo "现在重启ESP32以应用新配置..."
echo ""

# 重启ESP32
echo "restart" > $PORT
sleep 0.5

echo "✓ ESP32正在重启..."
echo ""
echo "等待ESP32连接到WiFi: $SSID"
echo ""
echo "查看串口日志:"
echo "  screen $PORT 115200"
echo ""
echo "或使用Flutter应用查看WiFi击锤状态"
