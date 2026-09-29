// Replay an explicitly supplied 16 kHz PCM16 mono fixture; never opens a microphone.
// Starts an isolated relay and tunnel proxy with an ephemeral token, no Meta key.
import { readFile } from "node:fs/promises";
import { createServer } from "node:http";
import { once } from "node:events";
import { randomBytes } from "node:crypto";
import assert from "node:assert/strict";
import { WebSocket } from "ws";
import { attachSpeech } from "../src/speech.ts";
import { hashToken } from "../src/security.ts";
import { createLiveCueProxy } from "../funnel/livecue-proxy.mjs";

const [model, file, repeats = "1"] = process.argv.slice(2);
assert.ok(["nemotron", "qwen3"].includes(model));
const wav = await readFile(file);
assert.equal(wav.toString("ascii", 0, 4), "RIFF");
let pcm: Buffer | undefined;
for (let i = 12; i + 8 <= wav.length;) {
  const size = wav.readUInt32LE(i + 4), kind = wav.toString("ascii", i, i + 4);
  if (kind === "fmt ") { assert.equal(wav.readUInt16LE(i + 8), 1); assert.equal(wav.readUInt16LE(i + 10), 1); assert.equal(wav.readUInt32LE(i + 12), 16000); assert.equal(wav.readUInt16LE(i + 22), 16); }
  if (kind === "data") pcm = wav.subarray(i + 8, i + 8 + size);
  i += 8 + size + (size % 2);
}
assert.ok(pcm?.length);
const audio = Buffer.concat(Array.from({ length: Math.min(5, Math.max(1, Number(repeats))) }, () => pcm!));
const token = randomBytes(32).toString("base64url");
const relay = createServer();
attachSpeech(relay, hashToken(token), {}, () => { throw Error("Meta must never be contacted"); }, "");
relay.listen(0, "127.0.0.1"); await once(relay, "listening");
const proxy = createLiveCueProxy({ port: (relay.address() as any).port });
const gateway = createServer(); gateway.on("upgrade", (req, socket, head) => proxy.upgrade(req, socket, head));
gateway.listen(0, "127.0.0.1"); await once(gateway, "listening");
const phone = new WebSocket(`ws://127.0.0.1:${(gateway.address() as any).port}/v1/speech`, { headers: { Authorization: `Bearer ${token}`, "X-LiveCue-Speech-Model": model } });
const start = performance.now(); let readyAt = 0, stoppedAt = 0, firstMs: number | undefined, finalMs = 0, turns = 0, words = 0, complete = false;
let failure: Error | undefined;
const deadline = setTimeout(() => phone.terminate(), 240000);
phone.on("message", async raw => {
  try {
    const e = JSON.parse(raw.toString());
    if (e.type === "error") throw Error(e.message);
    if (e.type === "ready") {
      assert.equal(e.provider, model); assert.equal(e.sampleRate, 16000); readyAt = performance.now();
      for (let offset = 0; offset < audio.length; offset += 2560) {
        if (phone.readyState !== WebSocket.OPEN) return;
        phone.send(audio.subarray(offset, offset + 2560));
        const due = readyAt + Math.min(audio.length, offset + 2560) / 32;
        await new Promise(r => setTimeout(r, Math.max(0, due - performance.now())));
      }
      stoppedAt = performance.now(); phone.send(JSON.stringify({ type: "endStream" }));
    }
    if (e.type === "transcript" && e.transcript && firstMs === undefined) firstMs = performance.now() - readyAt;
    if (e.type === "speechComplete" && e.transcript) { turns++; words += e.transcript.trim().split(/\s+/).length; }
    if (e.type === "streamComplete") { complete = true; finalMs = performance.now() - stoppedAt; assert.equal(e.audioProcessedMs, audio.length / 32); }
  } catch (error) { failure = error as Error; phone.close(); }
});
try {
  await once(phone, "close");
  if (failure) throw failure;
  assert.ok(complete && words > 0 && firstMs !== undefined, "Must receive partial and final captions");
  if (audio.length / 32000 > 32) assert.ok(turns >= 2, "Rolling windows must finalize more than one turn");
  console.log(JSON.stringify({ model, setupMs: Math.round(readyAt - start), audioSeconds: audio.length / 32000,
    firstTextMs: Math.round(firstMs!), finalizationMs: Math.round(finalMs), turns, words, result: "PASS" }));
} finally {
  clearTimeout(deadline); phone.terminate(); proxy.close(); gateway.close(); relay.close();
}
