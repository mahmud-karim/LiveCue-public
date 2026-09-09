import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { CodexRunner } from "./codex.ts";
import { bearerToken, verifyToken } from "./security.ts";

const maxBodyBytes = 128 * 1024;

export type RelayEvent = { type: string; [key: string]: unknown };
export type RelayControls = { emit?: (event: RelayEvent) => void; accepting?: () => boolean };
export function createLiveCueServer(tokenHash: string | (() => string), runner = new CodexRunner(), controls: RelayControls = {}) {
  let busy = false;
  return createServer(async (request, response) => {
    setSecurityHeaders(response);
    let trackedId: string | undefined;
    const expectedHash = typeof tokenHash === "function" ? tokenHash() : tokenHash;
    try {
      authenticate(request, expectedHash);
      controls.emit?.({ type: "phone-seen", time: new Date().toISOString() });
      if (request.method === "GET" && request.url === "/v1/health") {
        return json(response, 200, { ok: true });
      }
      if (request.method === "POST" && request.url === "/v1/pair/verify") return json(response, 200, { ok: true });
      if (request.method === "POST" && (request.url === "/v1/assist" || request.url === "/v1/session-summary")) {
        if (controls.accepting?.() === false) throw new HttpError(503, "PC relay is paused. Resume it in LiveCue Desktop.");
        if (busy) throw new HttpError(429, "The PC is processing another request. Try again shortly.");
        busy = true;
        try {
        const body = await readJson(request);
        const kind = request.url === "/v1/assist" ? "assist" : "summary";
        const requestId = kind === "assist" ? validateRequestId(body) : randomUUID();
        trackedId = requestId;
        const started = Date.now();
        controls.emit?.({ type: "request", requestId, kind, time: new Date().toISOString(), payload: body });
        const result = await runner.run(requestId, kind, body);
        controls.emit?.({ type: "reply", requestId, kind, durationMs: Date.now() - started, payload: result });
        return json(response, 200, result);
        } finally { busy = false; }
      }
      const match = /^\/v1\/requests\/([^/]+)$/.exec(request.url || "");
      if (request.method === "DELETE" && match) return json(response, runner.cancel(decodeURIComponent(match[1])) ? 200 : 404, { ok: true });
      json(response, 404, { error: "Endpoint not found." });
    } catch (error: unknown) {
      const status = error instanceof HttpError ? error.status : 500;
      if (trackedId) controls.emit?.({ type: "request-error", requestId: trackedId, message: "Assistant request failed or timed out. Check Codex sign-in and retry." });
      json(response, status, { error: status === 500 ? "The local assistant request failed." : (error as Error).message });
    }
  });
}

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}

function authenticate(request: IncomingMessage, expectedHash: string): void {
  const token = bearerToken(request.headers.authorization);
  if (!token || !verifyToken(token, expectedHash)) throw new HttpError(401, "Invalid pairing token.");
}

async function readJson(request: IncomingMessage): Promise<Record<string, unknown>> {
  const chunks: Buffer[] = []; let total = 0;
  for await (const chunk of request) {
    total += chunk.length;
    if (total > maxBodyBytes) throw new HttpError(413, "Request exceeds 128 KB.");
    chunks.push(chunk);
  }
  try {
    const value = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid object");
    return value as Record<string, unknown>;
  }
  catch { throw new HttpError(400, "Body must be valid JSON."); }
}

function validateRequestId(body: Record<string, unknown>): string {
  if (typeof body.requestId !== "string" || body.requestId.length > 80) throw new HttpError(400, "A valid requestId is required.");
  return body.requestId;
}

function setSecurityHeaders(response: ServerResponse): void {
  response.setHeader("Cache-Control", "no-store"); response.setHeader("X-Content-Type-Options", "nosniff");
}

function json(response: ServerResponse, status: number, body: unknown): void {
  if (response.writableEnded) return;
  response.writeHead(status, { "Content-Type": "application/json; charset=utf-8" }); response.end(JSON.stringify(body));
}
