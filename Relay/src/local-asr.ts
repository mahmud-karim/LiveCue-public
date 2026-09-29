import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { WebSocket } from "ws";
import type { RelayControls } from "./server.ts";

export type LocalModel = "nemotron" | "qwen3";
let preparation: Promise<void> | undefined;
export async function prepareLocalModel(model: LocalModel) {
  if (!["nemotron", "qwen3"].includes(model)) throw Error("Unsupported model");
  // A disconnect does not kill Docker mid-start; the next connection awaits that start.
  if (preparation) await preparation;
  try {
    const health = await (await fetch("http://127.0.0.1:8765/health", { signal: AbortSignal.timeout(1500) })).json() as any;
    if (health.busy) throw Error("busy");
    if (health.ready && health.model === model && health.relayProtocol === 1) return;
  } catch (error) { if ((error as Error).message === "busy") throw error; }
  const script = fileURLToPath(new URL("../../../LiveCue-ASR/Start-ASR-Lab.ps1", import.meta.url));
  // Do not give the model launcher the relay's API keys, tokens, or Codex environment.
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
    ["systemroot", "windir", "path", "pathext", "temp", "tmp", "userprofile", "appdata", "localappdata", "programdata", "programfiles", "programfiles(x86)", "comspec"].includes(key.toLowerCase())));
  const task = new Promise<void>((resolve, reject) => {
    execFile("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, "-Model", model, "-NoBrowser"],
      { windowsHide: true, timeout: 165000, maxBuffer: 512 * 1024, env }, error => error ? reject(Error("Local model startup failed")) : resolve());
  });
  preparation = task;
  try { await task; } finally { if (preparation === task) preparation = undefined; }
}

export const connectLocal = () => new WebSocket("ws://127.0.0.1:8765/relay", { maxPayload: 128 * 1024, handshakeTimeout: 5000 });

export function localSpeech(phone: WebSocket, model: LocalModel, authorized: () => boolean,
  controls: RelayControls, release: () => void,
  prepare = prepareLocalModel, connect = connectLocal) {
  let upstream: WebSocket | undefined;
  let closed = false, ready = false, ending = false, bytes = 0;
  const started = performance.now(); let lastAudio = started, readyAt = started, endedAt = 0;
  let preparing = true;
  const send = (event: object) => { if (phone.readyState === WebSocket.OPEN) phone.send(JSON.stringify(event)); };
  const finish = (message?: string) => {
    if (closed) return;
    closed = true; clearInterval(watchdog); upstream?.terminate();
    if (message) send({ type: "error", message });
    phone.close(message ? 1011 : 1000);
    // Keep the speech lease while a model switch is still running.
    if (!preparing) release();
    controls.emit?.({ type: "speech-status", message: message || `${model} transcription stopped.` });
  };
  const loading = () => send({ type: "loading", provider: model, message: `Loading ${model} on PC · ${Math.floor((performance.now() - started) / 1000)} s. Microphone starts when ready.` });
  loading(); controls.emit?.({ type: "speech-status", message: `Loading ${model} on the PC GPU…` });
  const watchdog = setInterval(() => {
    const now = performance.now();
    if (!authorized() || controls.accepting?.() === false) return finish("PC relay paused or pairing changed.");
    if (!ready) { if (now - started > 170000) finish("Model startup timed out. Check Docker Desktop, then retry."); else loading(); }
    else if (ending && now - endedAt > 12000) finish("Local model did not finalize in time. Some final words may be missing.");
    else if (!ending && now - lastAudio > 20000) finish("Audio stream timed out. Resume to reconnect.");
    else if (now - readyAt > 30 * 60000) finish("30-minute session limit reached. Pause and resume to continue.");
  }, 2000); watchdog.unref();
  phone.on("error", () => finish()); phone.on("close", () => finish());
  phone.on("message", (data, binary) => {
    if (!ready || ending || !upstream) return finish("Audio arrived outside an active transcription stream.");
    if (binary) {
      bytes += data.length; lastAudio = performance.now();
      if (data.length % 2 || bytes > 160000 + (lastAudio - readyAt) * 35 || upstream.bufferedAmount > 160000) return finish("Audio exceeded the live-stream buffer limit.");
      upstream.send(data);
    } else {
      try { if (JSON.parse(data.toString()).type !== "endStream") throw Error(); }
      catch { return finish("Unsupported speech command."); }
      ending = true; endedAt = performance.now(); upstream.send(JSON.stringify({ type: "endStream" }));
    }
  });
  void (async () => {
    try {
      await prepare(model);
      preparing = false;
      if (closed) { release(); return; }
      upstream = connect();
      upstream.on("error", () => finish("Local model connection failed. Check Docker Desktop and retry."));
      upstream.on("close", () => finish(ending ? undefined : "Local model disconnected. Resume to reconnect."));
      upstream.on("message", data => {
        try {
          const event = JSON.parse(data.toString());
          if (!ready) {
            if (event.type !== "ready" || event.model !== model || event.sampleRate !== 16000) return finish("The selected PC model is not ready or is busy. Retry after the other test stops.");
            ready = true; readyAt = lastAudio = performance.now();
            send({ type: "ready", provider: model, sampleRate: 16000, handshakeMs: readyAt - started });
            controls.emit?.({ type: "speech-status", message: `${model} ready · PC GPU · no speech API cost.` }); return;
          }
          if (event.type === "error") return finish("PC speech inference failed. Check the local model service and retry.");
          if (!["speechStart", "speechComplete", "transcript", "audioProgress", "streamComplete"].includes(event.type)) return;
          const clean: Record<string, unknown> = { type: event.type };
          for (const key of ["turnId", "audioProcessedMs", "finalizationMs"]) if (Number.isFinite(event[key])) clean[key] = event[key];
          if (typeof event.transcript === "string") clean.transcript = event.transcript.slice(0, 32000);
          send(clean);
          if (event.type === "speechComplete") controls.emit?.({ type: "speech-text", text: clean.transcript || "" });
          if (event.type === "streamComplete") { if (!ending) return finish("Unexpected local stream completion."); finish(); }
        } catch { finish("Unexpected local speech response."); }
      });
    } catch {
      preparing = false;
      if (closed) release(); else finish("Could not load the PC model. Start Docker Desktop, stop any lab test, and retry. No audio was sent to Meta.");
    }
  })();
}
