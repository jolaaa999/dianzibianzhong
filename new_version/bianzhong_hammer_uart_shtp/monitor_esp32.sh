#!/bin/bash
# ESP32日志查看脚本

echo "=========================================="
echo "  ESP32串口日志监视器"
echo "=========================================="
echo ""
echo "按 Ctrl+C 退出"
echo ""

stty -F /dev/ttyUSB0 115200 cs8 -cstopb -parenb raw

# 持续读取并过滤关键信息
cat /dev/ttyUSB0 | while IFS= read -r line; do
    # 过滤二进制数据，只显示可打印字符
    clean_line=$(echo "$line" | tr -cd '[:print:]\n')

    # 只显示包含关键词的行
    if echo "$clean_line" | grep -qE "(WiFi|IP|Strike|UDP|ang_vel|accel|jerk|connected|SSID)"; then
        echo "$clean_line"
    fi
done
