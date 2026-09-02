import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { CodexRunner } from "./codex.ts";
import { bearerToken, verifyToken } from "./security.ts";

const maxBodyBytes = 128 * 1024;

export function createLiveCueServer(tokenHash: string, runner = new CodexRunner()) {
  return createServer(async (request, response) => {
    setSecurityHeaders(response);
    try {
      if (request.method === "GET" && request.url === "/v1/health") {
        authenticate(request, tokenHash); return json(response, 200, { ok: true });
      }
      authenticate(request, tokenHash);
      if (request.method === "POST" && request.url === "/v1/pair/verify") return json(response, 200, { ok: true });
      if (request.method === "POST" && request.url === "/v1/assist") {
        const body = await readJson(request);
        const requestId = validateRequestId(body);
        return json(response, 200, await runner.run(requestId, "assist", body));
      }
      if (request.method === "POST" && request.url === "/v1/session-summary") {
        const body = await readJson(request);
        const requestId = typeof body.sessionId === "string" ? `summary-${body.sessionId}` : randomUUID();
        return json(response, 200, await runner.run(requestId, "summary", body));
      }
      const match = /^\/v1\/requests\/([^/]+)$/.exec(request.url || "");
      if (request.method === "DELETE" && match) return json(response, runner.cancel(decodeURIComponent(match[1])) ? 200 : 404, { ok: true });
      json(response, 404, { error: "Endpoint not found." });
    } catch (error: unknown) {
      const status = error instanceof HttpError ? error.status : 500;
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
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")) as Record<string, unknown>; }
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
