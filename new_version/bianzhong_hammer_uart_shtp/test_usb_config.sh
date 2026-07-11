#!/bin/bash
# USB击锤配置测试脚本

PORT=${1:-/dev/ttyUSB0}
BAUD=115200

echo "=========================================="
echo "  USB击锤配置测试"
echo "=========================================="
echo ""
echo "串口: $PORT"
echo "波特率: $BAUD"
echo ""

# 检查串口是否存在
if [ ! -e "$PORT" ]; then
    echo "错误: 串口 $PORT 不存在"
    echo ""
    echo "可用串口:"
    ls -1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || echo "  未找到串口设备"
    exit 1
fi

# 配置串口
stty -F $PORT $BAUD cs8 -cstopb -parenb raw

echo "测试命令:"
echo "  1. ping           - 测试连接"
echo "  2. read_config    - 读取配置"
echo "  3. restart        - 重启ESP32"
echo ""
echo "按 Ctrl+C 退出"
echo ""
echo "=========================================="
echo ""

# 发送ping命令
echo "发送: ping"
echo "ping" > $PORT
sleep 0.5

# 读取响应
timeout 2 cat $PORT &
CAT_PID=$!

sleep 2
kill $CAT_PID 2>/dev/null

echo ""
echo "=========================================="
echo ""
echo "手动测试:"
echo "  screen $PORT $BAUD"
echo ""
echo "或使用Flutter应用的USB配置面板"
