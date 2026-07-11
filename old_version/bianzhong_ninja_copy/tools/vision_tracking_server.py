#!/usr/bin/env python3
"""OpenCV 反光标记球视觉追踪服务 — PRD 方案一。

检测 USB 摄像头画面中的高亮反光球，通过 WebSocket 以 30Hz 推送归一化坐标。

用法:
    pip install -r tools/requirements.txt
    python tools/vision_tracking_server.py
    python tools/vision_tracking_server.py --camera 0 --port 8765 --preview

消息格式（与 Flutter VisionStickFrame 对齐）:
    {"type":"stick_frame","stick_id":1,"x":0.42,"y":0.68,"confidence":0.95,"visible":true,"timestamp":1710000000123}
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import threading
import time
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, HTTPServer
from typing import Dict, List, Optional, Set

try:
    import cv2
    import numpy as np
except ImportError as exc:
    raise SystemExit("请先安装: pip install opencv-python numpy") from exc

try:
    import websockets
except ImportError as exc:
    raise SystemExit("请先安装: pip install websockets") from exc


@dataclass
class TrackedStick:
    stick_id: int
    x: float
    y: float
    confidence: float
    visible: bool = True


class AutoThresholdCalibrator:
    """根据环境亮度自动估计反光球分割阈值。"""

    def __init__(self, sample_frames: int = 60) -> None:
        self.sample_frames = sample_frames
        self._samples: List[float] = []
        self._done = False
        self.threshold = 220

    @property
    def is_ready(self) -> bool:
        return self._done

    def feed(self, gray: np.ndarray) -> None:
        if self._done:
            return
        bright = float(np.percentile(gray, 99))
        mean = float(np.mean(gray))
        self._samples.append(bright)
        if len(self._samples) >= self.sample_frames:
            target = float(np.median(self._samples))
            self.threshold = int(max(160, min(245, target - 8)))
            self._done = True
            print(
                f"自动阈值校准完成: threshold={self.threshold} "
                f"(mean={mean:.1f}, brightP99={target:.1f})"
            )

    def progress(self) -> float:
        return min(1.0, len(self._samples) / max(1, self.sample_frames))


class ReflectiveBallTracker:
    """基于阈值分割的反光球检测与双目标追踪。"""

    def __init__(
        self,
        min_area: float = 64.0,
        max_area: float = 12000.0,
        blur_ksize: int = 5,
        threshold: int = 220,
    ) -> None:
        self.min_area = min_area
        self.max_area = max_area
        self.blur_ksize = blur_ksize
        self.threshold = threshold
        self._prev_centers: Dict[int, tuple[float, float]] = {}

    def detect(self, frame: np.ndarray) -> List[TrackedStick]:
        height, width = frame.shape[:2]
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if self.blur_ksize > 1:
            gray = cv2.GaussianBlur(gray, (self.blur_ksize, self.blur_ksize), 0)
        _, binary = cv2.threshold(gray, self.threshold, 255, cv2.THRESH_BINARY)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
        binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)
        binary = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)

        contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        candidates: List[tuple[float, float, float, float]] = []
        for contour in contours:
            area = cv2.contourArea(contour)
            if area < self.min_area or area > self.max_area:
                continue
            perimeter = cv2.arcLength(contour, True)
            if perimeter <= 0:
                continue
            circularity = 4 * math.pi * area / (perimeter * perimeter)
            if circularity < 0.45:
                continue
            moments = cv2.moments(contour)
            if moments["m00"] == 0:
                continue
            cx = moments["m10"] / moments["m00"]
            cy = moments["m01"] / moments["m00"]
            radius = math.sqrt(area / math.pi)
            confidence = min(1.0, circularity * 0.7 + min(radius / 24.0, 1.0) * 0.3)
            candidates.append((cx, cy, confidence, area))

        candidates.sort(key=lambda item: item[3], reverse=True)
        candidates = candidates[:2]
        candidates.sort(key=lambda item: item[0])

        assigned: List[TrackedStick] = []
        used_prev: Set[int] = set()
        for index, (cx, cy, confidence, _area) in enumerate(candidates, start=1):
            stick_id = self._assign_stick_id(index, cx / width, cy / height, used_prev)
            used_prev.add(stick_id)
            assigned.append(
                TrackedStick(
                    stick_id=stick_id,
                    x=max(0.0, min(1.0, cx / width)),
                    y=max(0.0, min(1.0, cy / height)),
                    confidence=confidence,
                    visible=True,
                )
            )
            self._prev_centers[stick_id] = (cx / width, cy / height)

        for stick_id in (1, 2):
            if stick_id not in {stick.stick_id for stick in assigned}:
                assigned.append(
                    TrackedStick(
                        stick_id=stick_id,
                        x=0.0,
                        y=0.0,
                        confidence=0.0,
                        visible=False,
                    )
                )

        assigned.sort(key=lambda stick: stick.stick_id)
        return assigned

    def _assign_stick_id(
        self,
        fallback_index: int,
        nx: float,
        ny: float,
        used_prev: Set[int],
    ) -> int:
        if not self._prev_centers:
            return fallback_index

        best_id = fallback_index
        best_dist = float("inf")
        for stick_id, (px, py) in self._prev_centers.items():
            if stick_id in used_prev:
                continue
            dist = (px - nx) ** 2 + (py - ny) ** 2
            if dist < best_dist:
                best_dist = dist
                best_id = stick_id
        if best_dist > 0.12:
            return fallback_index
        return best_id


class VisionTrackingRuntime:
    def __init__(
        self,
        camera_index: int,
        fps: int,
        preview: bool,
        tracker: ReflectiveBallTracker,
        calibrator: Optional[AutoThresholdCalibrator] = None,
    ) -> None:
        self.camera_index = camera_index
        self.fps = fps
        self.preview = preview
        self.tracker = tracker
        self.calibrator = calibrator
        self._latest_frames: List[TrackedStick] = []
        self._latest_jpeg: Optional[bytes] = None
        self._lock = threading.Lock()
        self._running = False
        self._thread: Optional[threading.Thread] = None
        self._capture: Optional[cv2.VideoCapture] = None

    def start(self) -> None:
        self._running = True
        self._thread = threading.Thread(target=self._capture_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._running = False
        if self._thread is not None:
            self._thread.join(timeout=2)
        if self._capture is not None:
            self._capture.release()
            self._capture = None
        if self.preview:
            cv2.destroyAllWindows()

    def latest_frames(self) -> List[TrackedStick]:
        with self._lock:
            return list(self._latest_frames)

    def get_snapshot_jpeg(self) -> Optional[bytes]:
        with self._lock:
            return self._latest_jpeg

    def _render_preview(self, frame, sticks: List[TrackedStick]):
        preview = frame.copy()
        height, width = preview.shape[:2]
        if self.calibrator is not None and not self.calibrator.is_ready:
            progress = int(self.calibrator.progress() * 100)
            cv2.putText(
                preview,
                f"Calibrating threshold... {progress}%",
                (20, 36),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 220, 255),
                2,
                cv2.LINE_AA,
            )
        for stick in sticks:
            if not stick.visible:
                continue
            px = int(stick.x * width)
            py = int(stick.y * height)
            color = (255, 200, 80) if stick.stick_id == 1 else (80, 200, 255)
            cv2.circle(preview, (px, py), 16, color, 2)
            cv2.putText(
                preview,
                f"#{stick.stick_id}",
                (px + 12, py - 12),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                color,
                2,
                cv2.LINE_AA,
            )
        return preview

    def _capture_loop(self) -> None:
        self._capture = cv2.VideoCapture(self.camera_index, cv2.CAP_DSHOW)
        if not self._capture.isOpened():
            raise RuntimeError(f"无法打开摄像头 index={self.camera_index}")

        self._capture.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
        self._capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)
        self._capture.set(cv2.CAP_PROP_FPS, self.fps)

        interval = 1.0 / self.fps
        while self._running:
            started = time.time()
            ok, frame = self._capture.read()
            if not ok:
                time.sleep(0.05)
                continue

            gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
            if self.calibrator is not None and not self.calibrator.is_ready:
                self.calibrator.feed(gray)
                self.tracker.threshold = self.calibrator.threshold

            sticks = self.tracker.detect(frame)
            preview = self._render_preview(frame, sticks)
            ok_jpeg, jpeg = cv2.imencode(
                ".jpg", preview, [int(cv2.IMWRITE_JPEG_QUALITY), 72]
            )
            with self._lock:
                self._latest_frames = sticks
                if ok_jpeg:
                    self._latest_jpeg = jpeg.tobytes()

            if self.preview:
                cv2.imshow("Bianzhong Vision Tracking", preview)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    self._running = False
                    break

            elapsed = time.time() - started
            if elapsed < interval:
                time.sleep(interval - elapsed)


class SnapshotHttpServer:
    """HTTP /snapshot 端点，供 Flutter 校准向导预览摄像头画面。"""

    def __init__(self, runtime: VisionTrackingRuntime, host: str, port: int) -> None:
        self._runtime = runtime
        self._host = host
        self._port = port
        self._httpd: Optional[HTTPServer] = None
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        runtime = self._runtime

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, format, *args) -> None:
                return

            def do_GET(self) -> None:
                if self.path.split("?", 1)[0] != "/snapshot":
                    self.send_response(404)
                    self.end_headers()
                    return
                data = runtime.get_snapshot_jpeg()
                if not data:
                    self.send_response(503)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Type", "image/jpeg")
                self.send_header("Cache-Control", "no-store")
                self.send_header("Access-Control-Allow-Origin", "*")
                self.end_headers()
                self.wfile.write(data)

        self._httpd = HTTPServer((self._host, self._port), Handler)
        self._thread = threading.Thread(target=self._httpd.serve_forever, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        if self._httpd is not None:
            self._httpd.shutdown()
            self._httpd = None


async def broadcast_loop(
    websocket,
    runtime: VisionTrackingRuntime,
    fps: int,
) -> None:
    interval = 1.0 / fps
    tick = 0
    while True:
        started = time.time()
        timestamp = int(time.time() * 1000)
        sticks = runtime.latest_frames()
        for stick in sticks:
            payload = {
                "type": "stick_frame",
                "stick_id": stick.stick_id,
                "x": round(stick.x, 4),
                "y": round(stick.y, 4),
                "confidence": round(stick.confidence, 3),
                "visible": stick.visible,
                "timestamp": timestamp,
            }
            await websocket.send(json.dumps(payload))

        tick += 1
        if tick >= fps:
            tick = 0
            calibrator = runtime.calibrator
            calibrating = calibrator is not None and not calibrator.is_ready
            await websocket.send(
                json.dumps(
                    {
                        "type": "tracker_status",
                        "threshold": runtime.tracker.threshold,
                        "calibrating": calibrating,
                        "calibration_progress": calibrator.progress()
                        if calibrator is not None
                        else 1.0,
                        "fps": fps,
                        "detected_sticks": sum(1 for s in sticks if s.visible),
                    }
                )
            )

        elapsed = time.time() - started
        if elapsed < interval:
            await asyncio.sleep(interval - elapsed)


async def ws_handler(websocket, runtime: VisionTrackingRuntime, fps: int) -> None:
    print(f"客户端已连接: {websocket.remote_address}")
    sender = asyncio.create_task(broadcast_loop(websocket, runtime, fps))
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
            except json.JSONDecodeError:
                continue
            if data.get("type") == "ping":
                await websocket.send(json.dumps({"type": "pong", "timestamp": int(time.time() * 1000)}))
            elif data.get("type") == "recalibrate_threshold":
                runtime.calibrator = AutoThresholdCalibrator()
                await websocket.send(
                    json.dumps(
                        {
                            "type": "calibration_started",
                            "threshold": runtime.tracker.threshold,
                        }
                    )
                )
            elif data.get("type") == "set_threshold":
                runtime.tracker.threshold = int(
                    max(160, min(245, data.get("threshold", runtime.tracker.threshold)))
                )
                runtime.calibrator = None
                await websocket.send(
                    json.dumps(
                        {
                            "type": "calibration_complete",
                            "threshold": runtime.tracker.threshold,
                        }
                    )
                )
    finally:
        sender.cancel()
        print("客户端已断开")


async def main() -> None:
    parser = argparse.ArgumentParser(description="编钟视觉追踪 WebSocket 服务")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--fps", type=int, default=30)
    parser.add_argument("--threshold", type=int, default=220)
    parser.add_argument(
        "--auto-threshold",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="启动时根据环境光自动校准阈值",
    )
    parser.add_argument("--preview", action="store_true", help="显示本地调试预览窗口")
    parser.add_argument(
        "--snapshot-port",
        type=int,
        default=8766,
        help="HTTP 快照预览端口（/snapshot）",
    )
    args = parser.parse_args()

    calibrator = AutoThresholdCalibrator() if args.auto_threshold else None
    tracker = ReflectiveBallTracker(threshold=args.threshold)
    runtime = VisionTrackingRuntime(
        camera_index=args.camera,
        fps=args.fps,
        preview=args.preview,
        tracker=tracker,
        calibrator=calibrator,
    )
    runtime.start()
    snapshot_server = SnapshotHttpServer(runtime, args.host, args.snapshot_port)
    snapshot_server.start()

    async def handler(websocket):
        await ws_handler(websocket, runtime, args.fps)

    print(
        f"视觉追踪服务: ws://{args.host}:{args.port}  camera={args.camera}  "
        f"fps={args.fps}  auto_threshold={args.auto_threshold}  "
        f"snapshot=http://{args.host}:{args.snapshot_port}/snapshot"
    )
    async with websockets.serve(handler, args.host, args.port):
        try:
            await asyncio.Future()
        finally:
            snapshot_server.stop()
            runtime.stop()


if __name__ == "__main__":
    asyncio.run(main())
