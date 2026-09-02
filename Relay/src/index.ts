import qrcode from "qrcode-terminal";
import { createLiveCueServer } from "./server.ts";
import { defaultConfigPath, loadOrCreatePairing } from "./security.ts";

const host = "127.0.0.1";
const port = Number(process.env.LIVECUE_PORT || 47831);
const reset = process.argv.includes("--reset-pairing");
const endpoint = process.env.LIVECUE_PUBLIC_ENDPOINT || `http://${host}:${port}`;
const { config, plaintextToken } = await loadOrCreatePairing(defaultConfigPath(), reset);
const server = createLiveCueServer(config.tokenHash);

server.listen(port, host, () => {
  console.log(`LiveCue Relay ready on ${endpoint}`);
  console.log("Codex model: gpt-5.6-sol · reasoning: low · speed tier: default");
  if (plaintextToken) {
    const payload = JSON.stringify({ endpoint, token: plaintextToken });
    console.log("\nPaste this pairing payload into LiveCue:\n");
    console.log(payload);
    qrcode.generate(payload, { small: true });
    console.log("This token is shown once. Use --reset-pairing to replace it.");
  } else {
    console.log("Using the existing pairing token. Run npm run reset-pairing to pair a new phone.");
  }
});

for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => server.close(() => process.exit(0)));

