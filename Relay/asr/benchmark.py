"""Replay the same public/synthetic fixture through the actual streaming socket."""
import argparse
import asyncio
import json
import math
import time
from pathlib import Path
import numpy as np
import soundfile as sf
from scipy.signal import resample_poly
import websockets


async def benchmark(args):
    pcm, rate = sf.read(args.audio, dtype="float32", always_2d=True)
    pcm = pcm.mean(axis=1)
    if rate != 16000:
        divisor = math.gcd(rate, 16000)
        pcm = resample_poly(pcm, 16000 // divisor, rate // divisor)
    pcm = (np.clip(pcm, -1, 1) * 32767).astype("<i2")
    async with websockets.connect("ws://127.0.0.1:8765/stream", max_size=1_000_000) as ws:
        ready = json.loads(await ws.recv())
        if ready.get("type") != "ready":
            raise RuntimeError(ready)
        start = time.perf_counter()
        changes = []

        async def send():
            for offset in range(0, len(pcm), 1280):
                part = pcm[offset:offset+1280]
                if not args.fast:
                    # Audio cannot be sent before it would have been captured.
                    await asyncio.sleep(max(0, (offset + len(part)) / 16000 - (time.perf_counter()-start)))
                await ws.send(part.tobytes())
            await ws.send(json.dumps({"type": "stop"}))

        sending = asyncio.create_task(send())
        async for raw in ws:
            event = json.loads(raw)
            if event["type"] == "error":
                raise RuntimeError(event)
            if event["type"] == "transcript":
                changes.append({"elapsedMs": event["elapsedMs"], "text": event["text"]})
            if event["type"] == "result":
                event["realtimePlayback"] = not args.fast
                event["partialUpdates"] = len(changes)
                event["fixture"] = Path(args.audio).name
                if args.reference:
                    from jiwer import wer, Compose, ToLowerCase, RemovePunctuation, RemoveMultipleSpaces, Strip, ReduceToListOfListOfWords
                    normalize = Compose([ToLowerCase(), RemovePunctuation(), RemoveMultipleSpaces(), Strip(), ReduceToListOfListOfWords()])
                    event["normalizedWER"] = wer(args.reference, event["text"], reference_transform=normalize, hypothesis_transform=normalize)
                print(json.dumps(event), flush=True)
                if args.output:
                    with open(args.output, "a", encoding="utf-8") as output:
                        output.write(json.dumps({**event, "updates": changes}) + "\n")
        await sending


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("audio")
    parser.add_argument("--reference")
    parser.add_argument("--output")
    parser.add_argument("--fast", action="store_true", help="Unpaced throughput smoke test, NOT live latency")
    asyncio.run(benchmark(parser.parse_args()))
