#!/usr/bin/env python3
"""Mock 视觉服务稳定性探测 — 无需摄像头，长跑监测 WS 推送稳定性。

用法:
    # 终端 1
    python tools/mock_vision_server.py

    # 终端 2
    python tools/mock_stability_probe.py --minutes 5
    python tools/mock_stability_probe.py --minutes 240 --report stability_report.json
"""

from __future__ import annotations

import argparse
import asyncio
import json
import statistics
import time
from dataclasses import dataclass, field

try:
    import websockets
except ImportError:
    raise SystemExit("请先安装: pip install websockets") from None


@dataclass
class StabilityStats:
    frames: int = 0
    disconnects: int = 0
    gaps_ms: list[float] = field(default_factory=list)
    started_at: float = field(default_factory=time.time)

    def to_dict(self) -> dict:
        elapsed = max(1.0, time.time() - self.started_at)
        avg_gap = statistics.mean(self.gaps_ms) if self.gaps_ms else 0.0
        p95_gap = (
            sorted(self.gaps_ms)[int(len(self.gaps_ms) * 0.95)]
            if len(self.gaps_ms) >= 20
            else (max(self.gaps_ms) if self.gaps_ms else 0.0)
        )
        loss_rate = 0.0
        if self.gaps_ms:
            stale_threshold = 80.0
            stale = sum(1 for gap in self.gaps_ms if gap > stale_threshold)
            loss_rate = stale / len(self.gaps_ms)
        return {
            "elapsed_seconds": round(elapsed, 1),
            "frames_received": self.frames,
            "disconnects": self.disconnects,
            "avg_frame_gap_ms": round(avg_gap, 2),
            "p95_frame_gap_ms": round(p95_gap, 2),
            "estimated_loss_rate": round(loss_rate, 4),
            "meets_prd_1pct_loss": loss_rate < 0.01,
        }


async def run_probe(url: str, minutes: float, report_path: str | None) -> None:
    stats = StabilityStats()
    end_at = time.time() + minutes * 60
    last_frame_at: float | None = None

    print(f"稳定性探测: {url}  时长 {minutes:.1f} 分钟")
    while time.time() < end_at:
        try:
            async with websockets.connect(url) as websocket:
                while time.time() < end_at:
                    raw = await asyncio.wait_for(websocket.recv(), timeout=2.0)
                    data = json.loads(raw)
                    if data.get("type") != "stick_frame":
                        continue
                    now = time.perf_counter()
                    if last_frame_at is not None:
                        stats.gaps_ms.append((now - last_frame_at) * 1000)
                    last_frame_at = now
                    stats.frames += 1
        except (asyncio.TimeoutError, websockets.exceptions.ConnectionClosed, OSError):
            stats.disconnects += 1
            last_frame_at = None
            await asyncio.sleep(1.0)

    result = stats.to_dict()
    print("\n=== 稳定性结果 ===")
    for key, value in result.items():
        print(f"{key}: {value}")

    if report_path:
        with open(report_path, "w", encoding="utf-8") as fp:
            json.dump(result, fp, ensure_ascii=False, indent=2)
        print(f"\n报告已写入: {report_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Mock 视觉服务稳定性探测")
    parser.add_argument("--url", default="ws://127.0.0.1:8765")
    parser.add_argument("--minutes", type=float, default=5.0)
    parser.add_argument("--report", default=None, help="JSON 报告输出路径")
    args = parser.parse_args()
    asyncio.run(run_probe(args.url, args.minutes, args.report))


if __name__ == "__main__":
    main()
