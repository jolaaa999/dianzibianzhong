# ESP32-S3 固件烧录说明

本目录是 ESP-IDF 工程。

## 编译产物

编译后主要产物：

- `build/bootloader/bootloader.bin`
- `build/partition_table/partition-table.bin`
- `build/bianzhong_hammer.bin`

## 使用项目脚本

```bash
cd /home/abc/桌面/321shuzibianz/firmware/bianzhong_hammer
./build.sh
./build.sh --upload -p /dev/ttyACM0
./build.sh --monitor -p /dev/ttyACM0
```

## 直接使用 ESP-IDF

```bash
cd /home/abc/桌面/321shuzibianz/firmware/bianzhong_hammer
source ~/esp/esp-idf/export.sh
idf.py set-target esp32s3
idf.py build
idf.py -p /dev/ttyACM0 flash monitor
```

## 直接使用 esptool

```bash
python -m esptool --chip esp32s3 -b 460800 \
  --before default_reset --after hard_reset write_flash \
  --flash_mode dio --flash_size 8MB --flash_freq 80m \
  0x0 build/bootloader/bootloader.bin \
  0x8000 build/partition_table/partition-table.bin \
  0x10000 build/bianzhong_hammer.bin
```
