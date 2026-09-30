import { WebSocket, WebSocketServer } from "ws";
import type { Server } from "node:http";
import { bearerToken, verifyToken, type TokenHashes } from "./security.ts";
import type { RelayControls } from "./server.ts";
import { localSpeech, prepareLocalModel, connectLocal } from "./local-asr.ts";

// Fixed destination and format: phones never choose an upstream URL or receive a provider key.
export function attachSpeech(server: Server, tokenHash: TokenHashes | (() => TokenHashes), controls: RelayControls,
  connect = () => new WebSocket("wss://api.meta.ai/v1/asr/realtime", { maxPayload: 128 * 1024, handshakeTimeout: 15000 }),
  apiKey = process.env.LIVECUE_META_API_KEY,
  local = { prepare: prepareLocalModel, connect: connectLocal }) {
  const hub = new WebSocketServer({ noServer: true, maxPayload: 16 * 1024, perMessageDeflate: false });
  let active = false;
  const hash = () => typeof tokenHash === "function" ? tokenHash() : tokenHash;
  server.on("upgrade", (request, socket, head) => {
    const token = bearerToken(request.headers.authorization);
    const reject = (status: number) => { socket.end(`HTTP/1.1 ${status} Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n`); };
    if (request.url !== "/v1/speech") return reject(404);
    // Browser origins are not supported; pairing credentials belong to the native app.
    if (request.headers.origin || !token || !verifyToken(token, hash())) return reject(401);
    const provider = request.headers["x-livecue-speech-model"] ?? "meta";
    if (!["meta", "nemotron", "qwen3"].includes(provider as string)) return reject(400);
    if ((provider === "meta" && !apiKey) || controls.accepting?.() === false) return reject(503);
    if (active) return reject(429);
    hub.handleUpgrade(request, socket, head, phone => {
      active = true;
      if (provider === "nemotron" || provider === "qwen3") {
        localSpeech(phone, provider, () => verifyToken(token, hash()), controls, () => { active = false; }, local.prepare, local.connect);
        return;
      }
      let upstream: WebSocket;
      try { upstream = connect(); } catch { active = false; phone.close(1011); return; }
      const started = performance.now();
      let ready = false, ending = false, closed = false, bytes = 0, lastAudio = started;
      const send = (value: object) => { if (phone.readyState === WebSocket.OPEN) phone.send(JSON.stringify(value)); };
      const finish = (message?: string) => {
        if (closed) return;
        closed = true; active = false; clearInterval(watchdog);
        if (message) send({ type: "error", message });
        upstream.terminate();
        phone.close(message ? 1011 : 1000);
        controls.emit?.({ type: "speech-status", message: message || "Cloud transcription stopped." });
      };
      const watchdog = setInterval(() => {
        const now = performance.now();
        if (!verifyToken(token, hash()) || controls.accepting?.() === false) finish("PC relay paused or pairing changed.");
        else if (now - started > 30 * 60_000) finish("30-minute cloud session limit reached. Pause and resume to continue.");
        else if (now - lastAudio > 20_000) finish("Audio stream timed out. Pause and resume to reconnect.");
      }, 1000);
      watchdog.unref();
      upstream.on("open", () => upstream.send(JSON.stringify({ authorization: { accessToken: `Bearer ${apiKey}` },
        model: "muse-voice-transcribe-1.0", audioEncoding: "PCM_24KHZ", mode: "ENDPOINTING", partialMode: "CUMULATIVE", emitAudioProgress: true })));
      upstream.on("message", raw => {
        try {
          const event = JSON.parse(raw.toString());
          if (!ready) {
            if (typeof event.sessionId !== "string") return finish("Meta authentication failed. Check the PC's API key and billing.");
            ready = true; send({ type: "ready", provider: "meta", sampleRate: 24000, handshakeMs: performance.now() - started });
            controls.emit?.({ type: "speech-status", message: "Meta Muse connected. Streaming live audio." });
            return;
          }
          if (event.type === "error") return finish("Meta transcription failed. Check billing or retry later.");
          if (!["speechStart", "speechEnd", "speechComplete", "transcript", "audioProgress"].includes(event.type)) return;
          // Construct an allowlisted object, never forward headers, metadata, or raw provider errors.
          const clean: Record<string, unknown> = { type: event.type };
          for (const name of ["turnId", "audioProcessedMs"]) if (typeof event[name] === "number") clean[name] = event[name];
          if (typeof event.final === "boolean") clean.final = event.final;
          if (typeof event.transcript === "string") clean.transcript = event.transcript.split(apiKey!).join("[redacted]").slice(0, 32000);
          send(clean);
          if (event.type === "speechComplete") controls.emit?.({ type: "speech-text", text: clean.transcript || "" });
        } catch { finish("Unexpected transcription response. Pause and resume to retry."); }
      });
      phone.on("message", (data, binary) => {
        if (!ready || ending) return finish("Audio arrived outside an active transcription stream.");
        if (binary) {
          bytes += data.length; lastAudio = performance.now();
          // 48 KB/s PCM, bounded burst and queued data; prevents uploaded files running up charges.
          if (data.length % 2 || bytes > 240000 + (lastAudio - started) * 52 || upstream.bufferedAmount > 240000) return finish("Audio exceeded the live-stream buffer limit.");
          upstream.send(data);
        } else {
          try { if (JSON.parse(data.toString()).type !== "endStream") throw Error(); }
          catch { return finish("Unsupported speech command."); }
          ending = true; upstream.send(JSON.stringify({ type: "endStream" }));
        }
      });
      upstream.on("error", () => finish("Could not connect to Meta. Check the PC internet connection and API access."));
      upstream.on("close", () => finish(ending ? undefined : "Cloud stream disconnected. Pause and resume to reconnect."));
      phone.on("error", () => finish()); phone.on("close", () => finish());
    });
  });
  server.on("close", () => { for (const client of hub.clients) client.terminate(); hub.close(); });
}
