"""Protocol tests without loading a GPU model or reading private audio."""
import time
import queue
import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect
import server
import numpy as np
from relay_stream import AudioWindow


def fake_recognize(frames, cancelled, emit):
    while not cancelled.is_set():
        try:
            part = frames.get(timeout=0.1)
        except queue.Empty:
            continue
        if part is None:
            emit({"type": "result", "text": "test caption"})
            return
        emit({"type": "transcript", "text": "test caption"})


class ProtocolTests(unittest.TestCase):
    def test_windows_preserve_every_sample_and_eof(self):
        source = queue.Queue()
        source.put(np.arange(7)); source.put(np.arange(7, 11)); source.put(None)
        carry = None; actual = []
        while True:
            window = AudioWindow(source, carry, limit=5)
            while (part := window.get()) is not None:
                actual.extend(part.tolist())
            carry = window.carry
            if window.eof:
                break
        self.assertEqual(actual, list(range(11)))

    def test_relay_protocol_and_finalization(self):
        with self.client.websocket_connect("/relay") as ws:
            self.assertEqual(ws.receive_json()["sampleRate"], 16000)
            self.assertEqual(ws.receive_json()["type"], "speechStart")
            ws.send_bytes(bytes(2560))
            self.assertEqual(ws.receive_json()["transcript"], "test caption")
            ws.send_json({"type": "endStream"})
            self.assertEqual(ws.receive_json()["type"], "speechComplete")
            result = ws.receive_json()
            self.assertEqual(result["type"], "streamComplete")
            self.assertEqual(result["audioProcessedMs"], 80)

    def test_relay_rejects_browser_origin(self):
        with self.assertRaises(WebSocketDisconnect):
            with self.client.websocket_connect("/relay", headers={"origin": "http://localhost:8765"}):
                self.fail("Browser accepted on native route")

    def setUp(self):
        self.patch = patch.object(server, "recognize", fake_recognize)
        self.patch.start()
        self.client = TestClient(server.app, base_url="http://127.0.0.1:8765",
                                 headers={"host": "127.0.0.1:8765"})

    def tearDown(self):
        self.patch.stop()
        deadline = time.monotonic() + 3
        while server.busy.locked() and time.monotonic() < deadline:
            time.sleep(0.02)

    def test_reject_foreign_origin(self):
        with self.assertRaises(WebSocketDisconnect):
            with self.client.websocket_connect("/stream", headers={"origin": "https://evil.example"}):
                self.fail("Foreign origin accepted")

    def test_reject_rebinding_host(self):
        with self.assertRaises(WebSocketDisconnect):
            with self.client.websocket_connect("/stream", headers={"host": "evil.example:8765"}):
                self.fail("Foreign host accepted")

    def test_pcm_stream_stop_and_metrics(self):
        with self.client.websocket_connect("/stream", headers={"origin": "http://127.0.0.1:8765"}) as ws:
            self.assertEqual(ws.receive_json()["type"], "ready")
            ws.send_bytes(bytes(2560))
            self.assertEqual(ws.receive_json()["type"], "transcript")
            ws.send_json({"type": "stop"})
            result = ws.receive_json()
            self.assertEqual(result["type"], "result")
            self.assertAlmostEqual(result["inputSeconds"], 0.08)
            self.assertGreaterEqual(result["finalizationMs"], 0)

    def test_odd_pcm_rejected(self):
        with self.client.websocket_connect("/stream") as ws:
            ws.receive_json()
            ws.send_bytes(b"x")
            self.assertEqual(ws.receive_json()["type"], "error")

    def test_single_active_session(self):
        with self.client.websocket_connect("/stream") as ws:
            ws.receive_json()
            with self.client.websocket_connect("/stream") as other:
                self.assertEqual(other.receive_json()["type"], "error")
            ws.send_json({"type": "stop"})
            self.assertEqual(ws.receive_json()["type"], "result")


if __name__ == "__main__":
    unittest.main()
