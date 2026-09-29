"""Loopback-only ASR lab. Models are pre-downloaded; no cloud calls or audio logs."""
import asyncio
import json
import os
import queue
import threading
import time
from pathlib import Path

import numpy as np
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
import torch

KIND = os.environ.get("ASR_MODEL", "nemotron")
RATE = 16000
MAX_SECONDS = 120
app = FastAPI()
busy = threading.Lock()
model = processor = None
load_seconds = 0.0


def load_model():
    global model, processor, load_seconds
    started = time.perf_counter()
    if not torch.cuda.is_available():
        raise RuntimeError("CUDA GPU is not available; refusing an accidental CPU benchmark.")
    torch.set_num_threads(4)
    if KIND == "nemotron":
        from transformers import AutoModelForRNNT, AutoProcessor
        processor = AutoProcessor.from_pretrained("/models", local_files_only=True)
        processor.set_num_lookahead_tokens(3)  # 320 ms, not an end-to-end latency promise.
        model = AutoModelForRNNT.from_pretrained("/models", local_files_only=True,
                                                 dtype=torch.float32).to("cuda").eval()
    elif KIND == "qwen3":
        from qwen_asr import Qwen3ASRModel
        model = Qwen3ASRModel.LLM(model="/models", gpu_memory_utilization=0.55,
                                  max_model_len=4096, max_num_seqs=1,
                                  max_num_batched_tokens=1024, limit_mm_per_prompt={"audio": 1},
                                  enforce_eager=True, max_new_tokens=128,
                                  dtype="float16")
    else:
        raise RuntimeError("Unknown fixed model selection")
    load_seconds = time.perf_counter() - started
    print(json.dumps({"event": "loaded", "model": KIND, "loadSeconds": load_seconds}), flush=True)


@app.get("/")
def home():
    return FileResponse("/app/index.html")


@app.get("/health")
def health():
    return {"model": KIND, "ready": model is not None, "loadSeconds": load_seconds,
            "sampleRate": RATE, "maxSeconds": MAX_SECONDS,
            "chunkMs": 320 if KIND == "nemotron" else 1000,
            "relayProtocol": 1, "busy": busy.locked()}


@app.get("/sample")
def sample():
    # Fixed synthetic fixture only: never accept arbitrary filesystem paths.
    return FileResponse("/app/private/fixtures/everyday.wav", media_type="audio/wav")


def recognize(audio_queue, cancelled, emit):
    """Consume incremental 16k mono float PCM, preserving model caches per stream."""
    def receive():
        while not cancelled.is_set():
            try:
                return audio_queue.get(timeout=1)
            except queue.Empty:
                continue
        return None

    if KIND == "qwen3":
        state = model.init_streaming_state(chunk_size_sec=1.0, unfixed_chunk_num=2,
                                           unfixed_token_num=5)
        text = ""
        calls = []
        while (part := receive()) is not None:
            start = time.perf_counter()
            model.streaming_transcribe(part, state)
            calls.append((time.perf_counter() - start) * 1000)
            if state.text != text:
                text = state.text
                emit({"type": "transcript", "text": text})
        if cancelled.is_set():
            return
        model.finish_streaming_transcribe(state)
        emit({"type": "transcript", "text": state.text})
        emit({"type": "result", "text": state.text,
              "processingCallP95Ms": float(np.percentile(calls, 95)) if calls else None})
    else:
        from transformers import TextStreamer
        # Keep only the small audio window needed by the feature extractor.
        pcm = np.empty(0, dtype=np.float32)
        base = 0
        eof = False

        def read_window(start, count):
            nonlocal pcm, base, eof
            while base + len(pcm) < start + count and not eof:
                part = receive()
                if part is None:
                    eof = True
                else:
                    pcm = np.concatenate((pcm, part))
            available_end = base + len(pcm)
            if cancelled.is_set() or start >= available_end:
                return None
            result = pcm[max(0, start - base): start - base + count]
            if len(result) < count:
                result = np.pad(result, (0, count - len(result)))
            # Retain overlap for the next mel window, not the complete recording.
            keep = max(base, start - processor.feature_extractor.n_fft)
            pcm = pcm[keep - base:]
            base = keep
            return result

        first = read_window(0, processor.num_samples_first_audio_chunk)
        if first is None:
            emit({"type": "result", "text": ""})
            return
        inputs = processor(first, sampling_rate=RATE, is_streaming=True,
                           is_first_audio_chunk=True, language="en-US", return_tensors="pt")
        inputs = inputs.to(model.device, dtype=model.dtype)

        def features():
            yield inputs.input_features[:, :processor.num_mel_frames_first_audio_chunk, :]
            index = processor.num_mel_frames_first_audio_chunk
            while not cancelled.is_set():
                start = index * processor.feature_extractor.hop_length - processor.feature_extractor.n_fft // 2
                chunk = read_window(start, processor.num_samples_per_audio_chunk)
                if chunk is None:
                    break
                values = processor(chunk, sampling_rate=RATE, is_streaming=True,
                                   is_first_audio_chunk=False, language="en-US", return_tensors="pt")
                yield values.to(model.device, dtype=model.dtype).input_features
                index += processor.num_mel_frames_per_audio_chunk
                if eof:
                    break

        class CaptionStreamer(TextStreamer):
            def __init__(self):
                super().__init__(processor.tokenizer, skip_special_tokens=True)
                self.text = ""

            def on_finalized_text(self, text, stream_end=False):
                self.text += text
                if text:
                    emit({"type": "transcript", "text": self.text.strip()})

        streamer = CaptionStreamer()
        with torch.inference_mode():
            model.generate(**{**inputs, "input_features": features(), "streamer": streamer})
        emit({"type": "result", "text": streamer.text.strip()})


@app.websocket("/stream")
async def stream(ws: WebSocket):
    # Browser access must originate from this exact local lab, never arbitrary websites.
    origin = ws.headers.get("origin")
    if ws.headers.get("host") not in ("127.0.0.1:8765", "localhost:8765") or (
        origin and origin not in ("http://127.0.0.1:8765", "http://localhost:8765")
    ):
        await ws.close(code=1008)
        return
    await ws.accept()
    if not busy.acquire(blocking=False):
        await ws.send_json({"type": "error", "message": "One test is already running."})
        await ws.close()
        return
    frames = queue.Queue(maxsize=1500)
    cancelled = threading.Event()
    events = asyncio.Queue(maxsize=2000)
    loop = asyncio.get_running_loop()
    start = time.perf_counter()
    audio_bytes = 0
    stopped_at = None
    first_text_at = None
    worker = None

    def emit(event):
        if not cancelled.is_set():
            loop.call_soon_threadsafe(events.put_nowait, event)

    def run():
        try:
            recognize(frames, cancelled, emit)
        except Exception as exc:
            print(f"inference error: {type(exc).__name__}: {exc}", flush=True)
            emit({"type": "error", "message": "Local inference failed. Inspect the local model service log."})
        finally:
            busy.release()

    async def send_events():
        nonlocal first_text_at
        while True:
            event = await events.get()
            elapsed = (time.perf_counter() - start) * 1000
            if event.get("text") and first_text_at is None:
                first_text_at = elapsed
            event["elapsedMs"] = elapsed
            event["audioMs"] = audio_bytes / 32
            if event["type"] == "result":
                event.update(model=KIND, firstTextMs=first_text_at,
                             finalizationMs=(time.perf_counter() - stopped_at) * 1000 if stopped_at else None,
                             inputSeconds=audio_bytes / 32000)
            await ws.send_json(event)
            if event["type"] in ("result", "error"):
                await ws.close()
                return

    sender = None
    try:
        await ws.send_json({"type": "ready", "model": KIND, "sampleRate": RATE})
        worker = threading.Thread(target=run, daemon=True)
        worker.start()
        sender = asyncio.create_task(send_events())
        while True:
            message = await asyncio.wait_for(ws.receive(), timeout=20)
            if message["type"] == "websocket.disconnect":
                break
            if "bytes" in message:
                data = message["bytes"]
                audio_bytes += len(data)
                if len(data) % 2 or len(data) > 64000 or audio_bytes > RATE * 2 * MAX_SECONDS:
                    raise ValueError("Audio limit exceeded")
                frames.put_nowait(np.frombuffer(data, dtype="<i2").astype(np.float32) / 32768)
            elif json.loads(message.get("text", "{}")) == {"type": "stop"}:
                stopped_at = time.perf_counter()
                frames.put_nowait(None)
                await asyncio.wait_for(sender, timeout=60)
                break
            else:
                raise ValueError("Unsupported command")
    except (WebSocketDisconnect, RuntimeError):
        pass
    except (ValueError, asyncio.TimeoutError, queue.Full):
        try:
            await ws.send_json({"type": "error", "message": "Test timed out or exceeded its 120-second limit."})
            await ws.close()
        except RuntimeError:
            pass
    finally:
        cancelled.set()
        if sender and not sender.done():
            sender.cancel()
        if worker is None:
            busy.release()


from relay_stream import install_relay
install_relay(app, busy, lambda *args: recognize(*args), KIND)

if __name__ == "__main__":
    load_model()
    # Compile lazy kernels before the page says Ready, using synthetic silence only.
    warm_frames = queue.Queue()
    for _ in range(25):
        warm_frames.put(np.zeros(1280, dtype=np.float32))
    warm_frames.put(None)
    recognize(warm_frames, threading.Event(), lambda event: None)
    print(json.dumps({"event": "warmup_complete", "model": KIND}), flush=True)
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8765, access_log=False, ws_max_size=65536)
