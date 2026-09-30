import { spawn } from "node:child_process";

// Ask the same current executable used for Assist. Do not read the shared
// models_cache.json: unrelated older Codex installations can overwrite it.
export function readCurrentCodexCatalog(executable = process.env.LIVECUE_CODEX_EXECUTABLE || "codex"): Promise<string> {
  return new Promise((resolve, reject) => {
    const env = { ...process.env }; delete env.LIVECUE_META_API_KEY;
    const child = spawn(executable, ["app-server", "--listen", "stdio://"], {
      env, stdio: ["pipe", "pipe", "ignore"], windowsHide: true, shell: false
    });
    let buffer = "", settled = false;
    const finish = (value?: string) => {
      if (settled) return; settled = true; clearTimeout(timer);
      child.stdin.end(); child.kill();
      value === undefined ? reject(Error("Codex catalog unavailable")) : resolve(value);
    };
    const timer = setTimeout(() => finish(), 12000);
    child.once("error", () => finish()); child.once("exit", () => finish());
    child.stdin.on("error", () => finish());
    const send = (value: unknown) => child.stdin.write(JSON.stringify(value) + "\n");
    child.stdout.on("data", chunk => {
      buffer += chunk;
      if (buffer.length > 1024 * 1024) return finish();
      let end;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        let message; try { message = JSON.parse(line); } catch { continue; }
        if (message.id === 1) {
          if (message.error) return finish();
          send({ method: "initialized" });
          send({ id: 2, method: "model/list", params: { limit: 100, includeHidden: false } });
        }
        if (message.id === 2) {
          if (message.error || !Array.isArray(message.result?.data) || message.result.nextCursor) return finish();
          // Retain only model-picker fields, never account/auth/protocol data.
          return finish(JSON.stringify({ models: message.result.data.map((m: any) => ({
            slug: m.model, display_name: m.displayName, visibility: m.hidden ? "hide" : "list",
            supported_reasoning_levels: (m.supportedReasoningEfforts || []).map((e: any) => ({ effort: e.reasoningEffort }))
          })) }));
        }
      }
    });
    send({ id: 1, method: "initialize", params: { clientInfo: { name: "livecue_catalog", title: "LiveCue", version: "0.5.6" } } });
  });
}

export class CurrentCatalogSource {
  private value?: string;
  private expires = 0;
  private pending?: Promise<string>;
  private load: () => Promise<string>;
  constructor(load = readCurrentCodexCatalog) { this.load = load; }
  async read(): Promise<string> {
    if (this.value && Date.now() < this.expires) return this.value;
    if (!this.pending) this.pending = this.load().then(value => {
      this.value = value; this.expires = Date.now() + 300000; return value;
    }).finally(() => { this.pending = undefined; });
    return this.pending;
  }
}
