"""Native relay protocol. Bounded rolling ASR windows; no audio written to disk."""
import asyncio
import json
import queue
import threading
import time
import numpy as np
from fastapi import WebSocket


class AudioWindow:
    """Split a continuous queue without losing samples at window boundaries."""
    def __init__(self, source, carry=None, limit=30 * 16000):
        self.source, self.carry, self.limit = source, carry, limit
        self.samples = 0
        self.eof = False

    def get(self, timeout=1):
        if self.samples >= self.limit or self.eof:
            return None
        part = self.carry
        if part is None:
            part = self.source.get(timeout=timeout)
        self.carry = None
        if part is None:
            self.eof = True
            return None
        remaining = self.limit - self.samples
        if len(part) > remaining:
            self.carry = part[remaining:]
            part = part[:remaining]
        self.samples += len(part)
        return part


def install_relay(app, busy, recognize, kind):
    @app.websocket("/relay")
    async def relay(ws: WebSocket):
        # Docker binds this service to loopback. No web origins or arbitrary hosts.
        if ws.headers.get("origin") or ws.headers.get("host") not in ("127.0.0.1:8765", "localhost:8765"):
            await ws.close(code=1008)
            return
        await ws.accept()
        if not busy.acquire(blocking=False):
            await ws.send_json({"type": "error", "message": "Model is busy."})
            await ws.close()
            return
        frames = queue.Queue(maxsize=128)  # ~10 seconds of normal 80 ms frames
        cancelled = threading.Event()
        events = asyncio.Queue(maxsize=256)
        loop = asyncio.get_running_loop()
        worker = sender = None
        audio_bytes = 0
        stopped_at = None

        def emit(event):
            def offer():
                if cancelled.is_set():
                    return
                try:
                    events.put_nowait(event)
                except asyncio.QueueFull:
                    cancelled.set()
            if not cancelled.is_set():
                loop.call_soon_threadsafe(offer)

        def run():
            try:
                offset = 0
                carry = None
                turn = 0
                while not cancelled.is_set():
                    window = AudioWindow(frames, carry)
                    turn += 1
                    emit({"type": "speechStart", "turnId": turn, "audioProcessedMs": offset / 16})

                    def forward(event):
                        if event["type"] in ("transcript", "result"):
                            emit({"type": "speechComplete" if event["type"] == "result" else "transcript",
                                  "turnId": turn, "transcript": event.get("text", ""),
                                  "audioProcessedMs": (offset + window.samples) / 16})
                    recognize(window, cancelled, forward)
                    offset += window.samples
                    carry = window.carry
                    if window.eof:
                        emit({"type": "streamComplete", "audioProcessedMs": offset / 16,
                              "finalizationMs": (time.perf_counter() - stopped_at) * 1000 if stopped_at else 0})
                        return
            except Exception as exc:
                # No raw exception text: third-party exceptions can include transcript/audio.
                print("relay inference failed: " + type(exc).__name__, flush=True)
                emit({"type": "error", "message": "Local inference failed."})
            finally:
                busy.release()

        async def send_events():
            while True:
                event = await events.get()
                await ws.send_json(event)
                if event["type"] in ("streamComplete", "error"):
                    await ws.close()
                    return

        try:
            await ws.send_json({"type": "ready", "model": kind, "sampleRate": 16000})
            worker = threading.Thread(target=run, daemon=True)
            worker.start()
            sender = asyncio.create_task(send_events())
            while True:
                message = await asyncio.wait_for(ws.receive(), timeout=20)
                if message["type"] == "websocket.disconnect":
                    break
                if message.get("bytes") is not None:
                    data = message["bytes"]
                    audio_bytes += len(data)
                    if not data or len(data) % 2 or len(data) > 16384 or audio_bytes > 32000 * 1800:
                        raise ValueError("Invalid PCM")
                    frames.put_nowait(np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768)
                elif json.loads(message.get("text", "{}")) == {"type": "endStream"}:
                    stopped_at = time.perf_counter()
                    frames.put_nowait(None)
                    await asyncio.wait_for(sender, timeout=12)
                    break
                else:
                    raise ValueError("Invalid command")
        except (ValueError, asyncio.TimeoutError, queue.Full):
            try:
                await ws.send_json({"type": "error", "message": "Local audio buffer or time limit exceeded."})
                await ws.close()
            except RuntimeError:
                pass
        except RuntimeError:
            pass
        finally:
            cancelled.set()
            if sender and not sender.done():
                sender.cancel()
            if worker is None:
                busy.release()
