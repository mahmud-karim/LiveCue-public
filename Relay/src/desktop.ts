// Private parent/child stdio channel. Never expose these controls over HTTP.
import { createRequire } from "node:module";
import { createInterface } from "node:readline";
import { CodexRunner } from "./codex.ts";
import { createLiveCueServer } from "./server.ts";
import { defaultConfigPath, loadOrCreatePairing, pairingCode, pairingHashes } from "./security.ts";

const require = createRequire(import.meta.url);
const QRCode = require("qrcode-terminal/vendor/QRCode");
const level = require("qrcode-terminal/vendor/QRCode/QRErrorCorrectLevel");
const emit = (event: unknown) => process.stdout.write(JSON.stringify(event) + "\n");
const endpoint = process.env.LIVECUE_PUBLIC_ENDPOINT;
if (!endpoint?.startsWith("https://")) throw new Error("Start this service through LiveCue Desktop with Tailscale connected.");
let { config, plaintextToken, created } = await loadOrCreatePairing(defaultConfigPath(), false);
let accepting = true;
let closing = false;
const runner = new CodexRunner();
const server = createLiveCueServer(() => pairingHashes(config), runner, { emit, accepting: () => accepting });
function showPairing(token: string) {
  const payload = JSON.stringify({ endpoint, token });
  const qr = new QRCode(-1, level.M); qr.addData(payload); qr.make();
  emit({ type: "pairing", endpoint, modules: qr.modules });
  // Verify the exact advertised address without logging or persisting its bearer.
  void fetch(new URL('/v1/health', endpoint), {headers: {Authorization: `Bearer ${token}`},
    redirect: 'error', signal: AbortSignal.timeout(10000)})
    .then(async response => {
      if (!response.ok || !(await response.json() as {ok?: boolean}).ok) throw new Error('Unavailable');
      emit({type: 'notice', message: process.env.LIVECUE_CONNECTION_MODE === 'funnel'
        ? 'Secure Funnel connection verified. The iPhone VPN is not required.' : 'Secure PC connection verified.'});
    }).catch(() => emit({type: 'notice', message: 'Pairing code created, but the advertised connection could not be verified. Check the PC tunnel before pairing.'}));
}
server.on("error", (error: NodeJS.ErrnoException) => {
  emit({ type: "fatal", message: error.code === "EADDRINUSE" ? "The relay port is already in use. Close the old LiveCue relay terminal, then click Start relay." : "Could not start the relay." });
  process.exitCode = 1; input.close();
});
server.listen(Number(process.env.LIVECUE_PORT || 47831), "127.0.0.1", () => {
  emit({ type: "ready", endpoint, model: "gpt-5.6-sol", accepting, cloudSpeechReady: Boolean(process.env.LIVECUE_META_API_KEY), port: (server.address() as { port: number }).port });
  if (plaintextToken && created) showPairing(plaintextToken);
  plaintextToken = undefined;
  if (!created) emit({ type: "notice", message: "Saved pairing restored. Existing iPhones reconnect automatically; Show QR keeps their pairing valid." });
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
      const fresh = await pairingCode(defaultConfigPath());
      config = fresh.config; showPairing(fresh.plaintextToken!);
    }
  }).catch(() => emit({ type: "notice", message: "The desktop command failed. Please retry." }));
});
input.on("close", shutdown);
process.on("SIGTERM", shutdown); process.on("SIGINT", shutdown);
