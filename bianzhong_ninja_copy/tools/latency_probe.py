#!/usr/bin/env python3
"""WebSocket 延迟探测工具 — 测量 ping RTT 与 stick_frame 推送间隔。

用法:
    pip install websockets
    python tools/latency_probe.py
    python tools/latency_probe.py --url ws://127.0.0.1:8765 --samples 20
"""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import time

try:
    import websockets
except ImportError:
    raise SystemExit("请先安装: pip install websockets") from None


async def probe(url: str, samples: int, listen_seconds: float) -> None:
    print(f"连接 {url} ...")
    frame_intervals: list[float] = []
    ping_rtts: list[float] = []

    async with websockets.connect(url) as websocket:
        listen_task = asyncio.create_task(_listen_frames(websocket, frame_intervals))

        for i in range(samples):
            started = time.perf_counter()
            await websocket.send(
                json.dumps({"type": "ping", "timestamp": int(time.time() * 1000)})
            )
            while True:
                raw = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                data = json.loads(raw)
                if data.get("type") == "pong":
                    ping_rtts.append((time.perf_counter() - started) * 1000)
                    break
            await asyncio.sleep(0.15)

        await asyncio.sleep(listen_seconds)
        listen_task.cancel()

    print("\n=== 延迟探测结果 ===")
    if ping_rtts:
        print(
            f"Ping RTT: min={min(ping_rtts):.1f}ms  "
            f"avg={statistics.mean(ping_rtts):.1f}ms  "
            f"max={max(ping_rtts):.1f}ms  (n={len(ping_rtts)})"
        )
    else:
        print("Ping RTT: 无样本")

    if frame_intervals:
        avg_interval = statistics.mean(frame_intervals)
        print(
            f"stick_frame 间隔: avg={avg_interval:.1f}ms  "
            f"≈ {1000 / avg_interval:.1f} Hz  (n={len(frame_intervals)})"
        )
    else:
        print("stick_frame 间隔: 无样本（服务端是否在推送？）")

    if ping_rtts:
        estimated_e2e = statistics.mean(ping_rtts) / 2 + 25
        print(f"估算客户端处理预算(不含摄像头): ~{estimated_e2e:.0f}ms + 视觉/音频处理")


async def _listen_frames(websocket, frame_intervals: list[float]) -> None:
    last_ts: float | None = None
    try:
        while True:
            raw = await websocket.recv()
            data = json.loads(raw)
            if data.get("type") != "stick_frame":
                continue
            now = time.perf_counter()
            if last_ts is not None:
                frame_intervals.append((now - last_ts) * 1000)
            last_ts = now
    except asyncio.CancelledError:
        return
    except websockets.exceptions.ConnectionClosed:
        return


def main() -> None:
    parser = argparse.ArgumentParser(description="编钟视觉追踪延迟探测")
    parser.add_argument("--url", default="ws://127.0.0.1:8765")
    parser.add_argument("--samples", type=int, default=10, help="ping 次数")
    parser.add_argument(
        "--listen-seconds",
        type=float,
        default=3.0,
        help="额外监听 stick_frame 的秒数",
    )
    args = parser.parse_args()
    asyncio.run(probe(args.url, args.samples, args.listen_seconds))


if __name__ == "__main__":
    main()
