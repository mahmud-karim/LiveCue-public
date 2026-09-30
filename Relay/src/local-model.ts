import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";

export type LocalModel = "nemotron" | "qwen3";
export type LocalModelStatus = { state: "stopped" | "starting" | "ready" | "stopping" | "error"; model: LocalModel | null; busy: boolean; elapsedSeconds: number; message: string };
type Health = { ready?: boolean; model?: string; busy?: boolean; relayProtocol?: number };
export type Runtime = { health: () => Promise<Health>; start: (model: LocalModel) => Promise<void>; stop: () => Promise<void> };
export class ModelControlError extends Error { status: number; constructor(status: number, message: string) { super(message); this.status = status; } }
export function localModel(value: unknown): LocalModel {
  if (value !== "nemotron" && value !== "qwen3") throw new ModelControlError(400, "Choose Nemotron or Qwen3.");
  return value;
}
const message = { start: "Could not load the PC model. Check Docker Desktop, available GPU memory and the installed model weights, then retry. No audio was sent to Meta.", stop: "Could not stop the PC model. Stop any active lab test and retry." };
function runScript(name: string, args: string[], timeout: number): Promise<void> {
  const script = fileURLToPath(new URL(`../../../LiveCue-ASR/${name}`, import.meta.url));
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) =>
    ["systemroot", "windir", "path", "pathext", "temp", "tmp", "userprofile", "appdata", "localappdata", "programdata", "programfiles", "programfiles(x86)", "comspec"].includes(key.toLowerCase())));
  return new Promise((resolve, reject) => execFile("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script, ...args],
    { windowsHide: true, timeout, maxBuffer: 512 * 1024, env }, error => error ? reject(Error("Local model operation failed")) : resolve()));
}
export const installedRuntime: Runtime = {
  health: async () => (await fetch("http://127.0.0.1:8765/health", { signal: AbortSignal.timeout(1500) })).json(),
  start: model => runScript("Start-ASR-Lab.ps1", ["-Model", model, "-NoBrowser", "-EnsureDocker"], 660000),
  stop: () => runScript("Stop-ASR-Lab.ps1", [], 45000)
};

// One operation at a time, shared by settings controls and speech startup.
export class LocalModelController {
  private current: LocalModelStatus = { state: "stopped", model: null, busy: false, elapsedSeconds: 0, message: "PC model is stopped." };
  private operation?: Promise<void>;
  private started = 0;
  private runtime: Runtime;
  private emit: (status: LocalModelStatus) => void;
  constructor(runtime: Runtime = installedRuntime, emit: (status: LocalModelStatus) => void = () => {}) { this.runtime = runtime; this.emit = emit; }
  get changing() { return Boolean(this.operation); }
  snapshot(): LocalModelStatus { return { ...this.current, elapsedSeconds: this.changing ? Math.floor((Date.now() - this.started) / 1000) : 0 }; }
  async status(): Promise<LocalModelStatus> {
    if (this.changing) return this.snapshot();
    const health = await this.runtime.health().catch(() => null);
    // Do not replace a newly started operation with a stale probe.
    if (this.changing) return this.snapshot();
    if (health?.ready && health.relayProtocol === 1 && (health.model === "nemotron" || health.model === "qwen3")) {
      this.current = { state: "ready", model: health.model, busy: Boolean(health.busy), elapsedSeconds: 0, message: health.busy ? "Model is in use. Stop the conversation or lab test before unloading." : "Model loaded on the PC GPU. Ready for live transcription." };
    } else if (this.current.state !== "error") {
      this.current = { state: "stopped", model: null, busy: Boolean(health?.busy), elapsedSeconds: 0, message: "PC model is stopped. Start opens Docker Desktop if needed." };
    }
    return this.snapshot();
  }
  private begin(state: "starting" | "stopping", model: LocalModel, work: () => Promise<void>): LocalModelStatus {
    if (this.changing) throw new ModelControlError(409, "A PC model operation is already in progress. Wait for it to finish.");
    this.started = Date.now();
    this.current = { state, model, busy: false, elapsedSeconds: 0, message: state === "starting" ? "Starting Docker and loading the PC model. First load can take several minutes." : "Unloading the PC model to free GPU memory…" };
    this.emit(this.snapshot());
    const task = Promise.resolve().then(work).then(() => {
      this.current = { state: state === "starting" ? "ready" : "stopped", model: state === "starting" ? model : null, busy: false, elapsedSeconds: 0, message: state === "starting" ? "PC model is ready." : "PC model stopped. GPU memory released." };
    }).catch(() => { this.current = { ...this.current, state: "error", elapsedSeconds: 0, message: state === "starting" ? message.start : message.stop }; });
    this.operation = task.finally(() => { this.operation = undefined; this.emit(this.snapshot()); });
    return this.snapshot();
  }
  start(model: LocalModel) { return this.begin("starting", localModel(model), async () => {
    const health = await this.runtime.health().catch(() => null);
    if (health?.busy) throw Error("Model in use");
    if (health?.ready && health.model === model && health.relayProtocol === 1) return;
    await this.runtime.start(model);
    const ready = await this.runtime.health();
    if (!ready.ready || ready.model !== model || ready.relayProtocol !== 1) throw Error("Model not ready");
  }); }
  stop(model: LocalModel) { return this.begin("stopping", localModel(model), async () => {
    const health = await this.runtime.health().catch(() => null);
    if (health?.busy || (health?.model && health.model !== model)) throw Error("Model in use or changed");
    await this.runtime.stop();
  }); }
  async prepare(model: LocalModel) {
    localModel(model);
    if (this.operation) await this.operation;
    const status = await this.status();
    if (status.busy) throw Error("Model in use");
    if (status.state === "ready" && status.model === model) return;
    this.start(model); await this.operation;
    if (this.current.state !== "ready" || this.current.model !== model) throw Error(message.start);
  }
}
export const localModels = new LocalModelController();
