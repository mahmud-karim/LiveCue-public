import assert from "node:assert/strict";
import test from "node:test";
import { spawn } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { createInterface } from "node:readline";

test("desktop IPC starts, produces a QR, rotates pairing, pauses and shuts down", { timeout: 15000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), "livecue-desktop-test-"));
  const configPath = join(directory, "relay.json");
  const child = spawn(process.execPath, ["--experimental-strip-types", fileURLToPath(new URL("../src/desktop.ts", import.meta.url))], {
    env: { ...process.env, LIVECUE_CONFIG_PATH: configPath, LIVECUE_PUBLIC_ENDPOINT: "https://pc.example.test/", LIVECUE_PORT: "0" },
    stdio: ["pipe", "pipe", "pipe"], windowsHide: true
  });
  const events: any[] = [];
  let diagnostics = "";
  child.stderr.on("data", data => { diagnostics += data.toString(); });
  const lines = createInterface({ input: child.stdout });
  lines.on("line", line => events.push(JSON.parse(line)));
  const exited = new Promise(resolve => child.on("exit", resolve));
  async function waitFor(predicate: () => boolean) {
    const until = Date.now() + 5000;
    while (!predicate()) {
      if (Date.now() > until || child.exitCode !== null) throw new Error("Desktop event not received: " + diagnostics);
      await new Promise(resolve => setTimeout(resolve, 20));
    }
  }
  try {
    await waitFor(() => events.some(e => e.type === "pairing"));
    const qr = events.find(e => e.type === "pairing");
    assert.ok(qr.modules.length >= 21);
    assert.ok(qr.modules.every((row: boolean[]) => row.length === qr.modules.length));
    assert.equal(qr.token, undefined); // Never included as printable transcript activity.
    const before = JSON.parse(await readFile(configPath, "utf8"));
    assert.equal(before.tokenHash.length, 64); assert.equal(before.token, undefined);
    child.stdin.write('{"action":"pair"}\n');
    await waitFor(() => events.filter(e => e.type === "pairing").length === 2);
    const after = JSON.parse(await readFile(configPath, "utf8"));
    assert.notEqual(before.tokenHash, after.tokenHash);
    child.stdin.write('{"action":"pause","paused":true}\n');
    await waitFor(() => events.some(e => e.type === "state" && e.accepting === false));
    const ready = events.find(e => e.type === "ready");
    assert.equal((await fetch(`http://127.0.0.1:${ready.port}/v1/health`)).status, 401);
    child.stdin.write('{"action":"shutdown"}\n');
    await exited;
    assert.equal(child.exitCode, 0);
  } finally {
    if (child.exitCode === null) { child.kill(); await exited; }
    lines.close(); await rm(directory, { recursive: true, force: true });
  }
});
