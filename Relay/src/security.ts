import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

export type PairingConfig = { tokenHash: string; createdAt: string };

export function hashToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

export function verifyToken(token: string, expectedHash: string): boolean {
  const actual = Buffer.from(hashToken(token), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export function defaultConfigPath(): string {
  return process.env.LIVECUE_CONFIG_PATH || join(process.env.LOCALAPPDATA || homedir(), "LiveCue", "relay.json");
}

export async function loadOrCreatePairing(configPath: string, reset: boolean): Promise<{ config: PairingConfig; plaintextToken?: string }> {
  if (!reset) {
    try { return { config: JSON.parse(await readFile(configPath, "utf8")) as PairingConfig }; }
    catch (error: unknown) { if ((error as NodeJS.ErrnoException).code !== "ENOENT") throw error; }
  }
  const plaintextToken = randomBytes(32).toString("base64url");
  const config = { tokenHash: hashToken(plaintextToken), createdAt: new Date().toISOString() };
  await mkdir(dirname(configPath), { recursive: true });
  await writeFile(configPath, JSON.stringify(config, null, 2), { encoding: "utf8", mode: 0o600 });
  return { config, plaintextToken };
}

export function bearerToken(header: string | undefined): string | null {
  const match = /^Bearer\s+(.+)$/i.exec(header || "");
  return match?.[1] || null;
}

