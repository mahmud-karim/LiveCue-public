import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, writeFile, rename } from "node:fs/promises";
import { spawn } from "node:child_process";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

export type PairingConfig = { tokenHash: string; createdAt: string; protectedToken?: string; previousTokenHash?: string };
export type TokenHashes = string | string[];
export function pairingHashes(config: PairingConfig): string[] {
  return [config.tokenHash, config.previousTokenHash].filter((hash): hash is string => Boolean(hash));
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function verifyToken(token: string, expectedHash: TokenHashes): boolean {
  const actual = Buffer.from(hashToken(token), "hex");
  let accepted = false;
  for (const hash of typeof expectedHash === "string" ? [expectedHash] : expectedHash) {
    const expected = Buffer.from(hash, "hex");
    if (actual.length === expected.length && timingSafeEqual(actual, expected)) accepted = true;
  }
  return accepted;
}

// DPAPI binds the redisplayable QR credential to this Windows account. Secrets
// travel over private stdin/stdout, never process arguments or diagnostic logs.
async function protectToken(value: string, decrypt = false): Promise<string> {
  if (process.platform !== "win32") throw new Error("Pairing credential storage requires Windows DPAPI.");
  const operation = decrypt ? "Unprotect" : "Protect";
  const script = `Add-Type -AssemblyName System.Security; $taskBytes=[Convert]::FromBase64String([Console]::In.ReadToEnd().Trim()); $taskResult=[Security.Cryptography.ProtectedData]::${operation}($taskBytes,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser); [Console]::Out.Write([Convert]::ToBase64String($taskResult))`;
  return new Promise((resolve, reject) => {
    const child = spawn(join(process.env.SystemRoot || "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe"), ["-NoProfile", "-NonInteractive", "-Command", script], {
      windowsHide: true, stdio: ["pipe", "pipe", "pipe"],
      env: { SystemRoot: process.env.SystemRoot || "C:\\Windows", TEMP: process.env.TEMP, TMP: process.env.TMP }
    });
    let output = "";
    const timeout = setTimeout(() => { child.kill(); reject(new Error("Pairing storage timed out.")); }, 10000);
    child.stdout.on("data", data => { output += data.toString(); });
    child.stderr.resume();
    child.on("error", () => { clearTimeout(timeout); reject(new Error("Could not open protected pairing storage.")); });
    child.on("exit", code => {
      clearTimeout(timeout);
      if (code !== 0 || !output || output.length > 8192) return reject(new Error("Could not read or save protected pairing storage."));
      resolve(decrypt ? Buffer.from(output, "base64").toString("utf8") : output);
    });
    child.stdin.on("error", () => {});
    child.stdin.end(decrypt ? value : Buffer.from(value).toString("base64"));
  });
}

async function saveConfig(configPath: string, config: PairingConfig) {
  await mkdir(dirname(configPath), { recursive: true });
  const temporary = configPath + ".pending";
  await writeFile(temporary, JSON.stringify(config, null, 2), { encoding: "utf8", mode: 0o600 });
  await rename(temporary, configPath);
}

export function defaultConfigPath(): string {
  return process.env.LIVECUE_CONFIG_PATH || join(process.env.LOCALAPPDATA || homedir(), "LiveCue", "relay.json");
}

export async function loadOrCreatePairing(configPath: string, reset: boolean): Promise<{ config: PairingConfig; plaintextToken?: string; created?: boolean }> {
  if (!reset) {
    try {
      const config = JSON.parse(await readFile(configPath, "utf8")) as PairingConfig;
      if (!/^[a-f0-9]{64}$/.test(config.tokenHash)) throw new Error("Invalid saved pairing configuration.");
      const plaintextToken = config.protectedToken ? await protectToken(config.protectedToken, true) : undefined;
      if (plaintextToken && !verifyToken(plaintextToken, config.tokenHash)) throw new Error("Saved pairing credential does not match.");
      return { config, plaintextToken };
    }
    catch (error: unknown) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const plaintextToken = randomBytes(32).toString("base64url");
  const config = { tokenHash: hashToken(plaintextToken), createdAt: new Date().toISOString(), protectedToken: await protectToken(plaintextToken) };
  await saveConfig(configPath, config);
  return { config, plaintextToken, created: true };
}

export async function pairingCode(configPath: string): Promise<{ config: PairingConfig; plaintextToken: string }> {
  const saved = await loadOrCreatePairing(configPath, false);
  if (saved.plaintextToken) return { config: saved.config, plaintextToken: saved.plaintextToken };
  // Old releases saved only the hash. Add a recoverable code while retaining
  // the old phone's credential instead of forcing it to pair again.
  const plaintextToken = randomBytes(32).toString("base64url");
  const config: PairingConfig = { ...saved.config, previousTokenHash: saved.config.tokenHash,
    tokenHash: hashToken(plaintextToken), protectedToken: await protectToken(plaintextToken) };
  await saveConfig(configPath, config);
  return { config, plaintextToken };
}

export function bearerToken(header: string | undefined): string | null {
  const match = /^Bearer\s+(.+)$/i.exec(header || "");
  return match?.[1] || null;
}
