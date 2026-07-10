#!/usr/bin/env python3
"""视觉追踪 Mock WebSocket 服务器 — 用于前端独立联调。

用法:
    pip install websockets
    python tools/mock_vision_server.py

默认监听 ws://127.0.0.1:8765，以 30Hz 推送双 stick 正弦轨迹。
"""

import asyncio
import json
import math
import time

try:
    import websockets
except ImportError:
    print("请先安装: pip install websockets")
    raise

HOST = "127.0.0.1"
PORT = 8765
FPS = 30


async def handler(websocket):
    print(f"客户端已连接: {websocket.remote_address}")
    t0 = time.time()
    try:
        while True:
            t = time.time() - t0
            frames = [
                {
                    "type": "stick_frame",
                    "stick_id": 1,
                    "x": 0.5 + 0.3 * math.sin(t * 1.2),
                    "y": 0.5 + 0.2 * math.cos(t * 0.9),
                    "confidence": 0.92,
                    "visible": True,
                    "timestamp": int(time.time() * 1000),
                },
                {
                    "type": "stick_frame",
                    "stick_id": 2,
                    "x": 0.5 + 0.25 * math.sin(t * 1.5 + 1.0),
                    "y": 0.5 + 0.25 * math.cos(t * 1.1 + 0.5),
                    "confidence": 0.88,
                    "visible": True,
                    "timestamp": int(time.time() * 1000),
                },
            ]
            for frame in frames:
                await websocket.send(json.dumps(frame))
            await asyncio.sleep(1 / FPS)
    except websockets.exceptions.ConnectionClosed:
        print("客户端已断开")


async def main():
    async with websockets.serve(handler, HOST, PORT):
        print(f"Mock 视觉追踪服务: ws://{HOST}:{PORT}")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
