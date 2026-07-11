#!/bin/bash
# ESP-IDF build/flash helper for the ESP32-S3 hammer firmware.

set -e

FIRMWARE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IDF_EXPORT="${IDF_EXPORT:-$HOME/esp/esp-idf/export.sh}"

if [[ ! -f "$IDF_EXPORT" ]]; then
    echo "ESP-IDF export script not found: $IDF_EXPORT"
    exit 1
fi

source "$IDF_EXPORT" >/dev/null

ACTION="build"
PORT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--upload|flash)
            ACTION="flash"
            shift
            ;;
        -m|--monitor)
            ACTION="monitor"
            shift
            ;;
        -c|--clean)
            ACTION="clean"
            shift
            ;;
        -p|--port)
            PORT="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--upload|--monitor|--clean] [-p PORT]"
            exit 1
            ;;
    esac
done

detect_port() {
    if [[ -n "$PORT" ]]; then
        return
    fi
    if [[ -e /dev/ttyACM0 ]]; then
        PORT=/dev/ttyACM0
    elif [[ -e /dev/ttyUSB0 ]]; then
        PORT=/dev/ttyUSB0
    fi
}

cd "$FIRMWARE_DIR"
idf.py set-target esp32s3 >/dev/null

case "$ACTION" in
    build)
        idf.py build
        ;;
    flash)
        detect_port
        if [[ -z "$PORT" ]]; then
            echo "No serial port found. Use -p /dev/ttyACM0 or -p /dev/ttyUSB0."
            exit 1
        fi
        idf.py -p "$PORT" flash
        ;;
    monitor)
        detect_port
        if [[ -z "$PORT" ]]; then
            echo "No serial port found. Use -p /dev/ttyACM0 or -p /dev/ttyUSB0."
            exit 1
        fi
        idf.py -p "$PORT" monitor
        ;;
    clean)
        idf.py fullclean
        ;;
esac
