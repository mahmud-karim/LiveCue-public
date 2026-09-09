// Private parent/child stdio channel. Never expose these controls over HTTP.
import { createRequire } from "node:module";
import { createInterface } from "node:readline";
import { CodexRunner } from "./codex.ts";
import { createLiveCueServer } from "./server.ts";
import { defaultConfigPath, loadOrCreatePairing } from "./security.ts";

const require = createRequire(import.meta.url);
const QRCode = require("qrcode-terminal/vendor/QRCode");
const level = require("qrcode-terminal/vendor/QRCode/QRErrorCorrectLevel");
const emit = (event: unknown) => process.stdout.write(JSON.stringify(event) + "\n");
const endpoint = process.env.LIVECUE_PUBLIC_ENDPOINT;
if (!endpoint?.startsWith("https://")) throw new Error("Start this service through LiveCue Desktop with Tailscale connected.");
let { config, plaintextToken } = await loadOrCreatePairing(defaultConfigPath(), false);
let accepting = true;
let closing = false;
const runner = new CodexRunner();
const server = createLiveCueServer(() => config.tokenHash, runner, { emit, accepting: () => accepting });
function showPairing(token: string) {
  const payload = JSON.stringify({ endpoint, token });
  const qr = new QRCode(-1, level.M); qr.addData(payload); qr.make();
  emit({ type: "pairing", endpoint, modules: qr.modules });
}
server.on("error", (error: NodeJS.ErrnoException) => {
  emit({ type: "fatal", message: error.code === "EADDRINUSE" ? "The relay port is already in use. Close the old LiveCue relay terminal, then click Start relay." : "Could not start the relay." });
  process.exitCode = 1; input.close();
});
server.listen(Number(process.env.LIVECUE_PORT || 47831), "127.0.0.1", () => {
  emit({ type: "ready", endpoint, model: "gpt-5.6-sol", accepting, port: (server.address() as { port: number }).port });
  if (plaintextToken) { showPairing(plaintextToken); plaintextToken = undefined; }
});
function shutdown() {
  if (closing) return; closing = true;
  for (const id of runner.active.keys()) runner.cancel(id);
  server.close(() => process.exit(0));
  server.closeAllConnections();
  setTimeout(() => process.exit(0), 1500).unref();
}
const input = createInterface({ input: process.stdin, crlfDelay: Infinity });
let chain = Promise.resolve();
input.on("line", line => {
  if (line.length > 1024) return;
  chain = chain.then(async () => {
    const command = JSON.parse(line);
    if (command.action === "shutdown") { shutdown(); return; }
    if (command.action === "pause") { accepting = !Boolean(command.paused); emit({ type: "state", accepting }); }
    if (command.action === "pair") {
      const fresh = await loadOrCreatePairing(defaultConfigPath(), true);
      config = fresh.config; showPairing(fresh.plaintextToken!);
    }
  }).catch(() => emit({ type: "notice", message: "The desktop command failed. Please retry." }));
});
input.on("close", shutdown);
process.on("SIGTERM", shutdown); process.on("SIGINT", shutdown);
