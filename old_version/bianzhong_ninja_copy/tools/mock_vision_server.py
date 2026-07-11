#!/usr/bin/env python3
"""视觉追踪 Mock WebSocket 服务器 — 用于前端独立联调。

用法:
    pip install websockets
    python tools/mock_vision_server.py
    python tools/mock_vision_server.py --strike-demo

默认监听 ws://127.0.0.1:8765，以 30Hz 推送双 stick 坐标。
`--strike-demo` 模式会在编钟位置模拟「快速靠近 + 急停」敲击轨迹。
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import random
import time

try:
    import websockets
except ImportError:
    print("请先安装: pip install websockets")
    raise

HOST = "127.0.0.1"
PORT = 8765
FPS = 30

BELL_TARGETS = [
    (0.10, 0.78),
    (0.23, 0.78),
    (0.36, 0.78),
    (0.50, 0.78),
    (0.64, 0.78),
    (0.77, 0.78),
    (0.90, 0.78),
    (0.25, 0.27),
    (0.375, 0.27),
    (0.50, 0.27),
    (0.625, 0.27),
    (0.75, 0.27),
]


class MockTrackerState:
    threshold: int = 220
    calibrating: bool = False
    calibration_progress: float = 1.0


def idle_frames(t: float) -> list[dict]:
    ts = int(time.time() * 1000)
    return [
        {
            "type": "stick_frame",
            "stick_id": 1,
            "x": 0.5 + 0.3 * math.sin(t * 1.2),
            "y": 0.5 + 0.2 * math.cos(t * 0.9),
            "confidence": 0.92,
            "visible": True,
            "timestamp": ts,
        },
        {
            "type": "stick_frame",
            "stick_id": 2,
            "x": 0.5 + 0.25 * math.sin(t * 1.5 + 1.0),
            "y": 0.5 + 0.25 * math.cos(t * 1.1 + 0.5),
            "confidence": 0.88,
            "visible": True,
            "timestamp": ts,
        },
    ]


class StrikeDemoState:
    def __init__(self) -> None:
        self.phase = 0.0
        self.target = random.choice(BELL_TARGETS)
        self.start = (0.5, 0.15)
        self.hold_until = 0.0

    def next_target(self) -> None:
        self.target = random.choice(BELL_TARGETS)
        self.start = (
            0.5 + random.uniform(-0.08, 0.08),
            0.12 + random.uniform(0, 0.08),
        )
        self.phase = 0.0

    def frame(self, stick_id: int, _t: float) -> dict:
        now = time.time()
        if now >= self.hold_until:
            self.phase = min(1.0, self.phase + 0.08)
        else:
            self.phase = 0.0

        if self.phase >= 1.0:
            self.hold_until = now + random.uniform(0.35, 0.8)
            self.next_target()

        ease = 1 - pow(1 - self.phase, 3)
        offset = 0.03 if stick_id == 2 else 0.0
        x = self.start[0] + (self.target[0] - self.start[0]) * ease + offset
        y = self.start[1] + (self.target[1] - self.start[1]) * ease

        return {
            "type": "stick_frame",
            "stick_id": stick_id,
            "x": max(0.0, min(1.0, x)),
            "y": max(0.0, min(1.0, y)),
            "confidence": 0.9,
            "visible": True,
            "timestamp": int(time.time() * 1000),
        }


async def _message_loop(websocket, state: MockTrackerState) -> None:
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
            except json.JSONDecodeError:
                continue
            msg_type = data.get("type")
            if msg_type == "ping":
                await websocket.send(
                    json.dumps({"type": "pong", "timestamp": int(time.time() * 1000)})
                )
            elif msg_type == "recalibrate_threshold":
                state.calibrating = True
                state.calibration_progress = 0.0
                await websocket.send(
                    json.dumps(
                        {
                            "type": "calibration_started",
                            "threshold": state.threshold,
                        }
                    )
                )
                for step in (0.33, 0.66, 1.0):
                    await asyncio.sleep(0.2)
                    state.calibration_progress = step
                    state.threshold = 218 if step >= 1.0 else state.threshold
                state.calibrating = False
                await websocket.send(
                    json.dumps(
                        {
                            "type": "calibration_complete",
                            "threshold": state.threshold,
                        }
                    )
                )
            elif msg_type == "set_threshold":
                state.threshold = int(
                    max(160, min(245, data.get("threshold", state.threshold)))
                )
                state.calibrating = False
                state.calibration_progress = 1.0
                await websocket.send(
                    json.dumps(
                        {
                            "type": "calibration_complete",
                            "threshold": state.threshold,
                        }
                    )
                )
            elif msg_type == "strike_ack":
                pass
    except websockets.exceptions.ConnectionClosed:
        return


async def _push_frames(websocket, t0: float, demo: StrikeDemoState | None) -> None:
    t = time.time() - t0
    if demo is not None:
        frames = [demo.frame(1, t), demo.frame(2, t)]
    else:
        frames = idle_frames(t)
    for frame in frames:
        await websocket.send(json.dumps(frame))


async def _send_tracker_status(
    websocket, state: MockTrackerState, fps: int, detected_sticks: int
) -> None:
    await websocket.send(
        json.dumps(
            {
                "type": "tracker_status",
                "threshold": state.threshold,
                "calibrating": state.calibrating,
                "calibration_progress": state.calibration_progress,
                "fps": fps,
                "detected_sticks": detected_sticks,
            }
        )
    )


async def stream_handler(websocket, strike_demo: bool, fps: int) -> None:
    print(f"客户端已连接: {websocket.remote_address}")
    t0 = time.time()
    demo = StrikeDemoState() if strike_demo else None
    state = MockTrackerState()
    message_task = asyncio.create_task(_message_loop(websocket, state))
    tick = 0
    try:
        while True:
            await _push_frames(websocket, t0, demo)
            tick += 1
            if tick >= fps:
                tick = 0
                await _send_tracker_status(websocket, state, fps, 2)
            await asyncio.sleep(1 / fps)
    except websockets.exceptions.ConnectionClosed:
        print("客户端已断开")
    finally:
        message_task.cancel()


async def main() -> None:
    parser = argparse.ArgumentParser(description="Mock 视觉追踪 WebSocket 服务")
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--fps", type=int, default=FPS)
    parser.add_argument(
        "--strike-demo",
        action="store_true",
        help="模拟向编钟位置敲击的轨迹",
    )
    args = parser.parse_args()

    async def ws_handler(websocket):
        await stream_handler(websocket, args.strike_demo, args.fps)

    async with websockets.serve(ws_handler, args.host, args.port):
        mode = "strike-demo" if args.strike_demo else "idle"
        print(f"Mock 视觉追踪服务: ws://{args.host}:{args.port}  mode={mode}")
        await asyncio.Future()


if __name__ == "__main__":
    asyncio.run(main())
