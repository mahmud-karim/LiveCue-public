import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID } from "node:crypto";
import { CodexRunner } from "./codex.ts";
import { bearerToken, verifyToken, type TokenHashes } from "./security.ts";
import { modelCatalog, validateSelection, CatalogUnavailableError, SelectionUnavailableError } from "./models.ts";
import { attachSpeech } from "./speech.ts";
import { LocalModelController, installedRuntime, localModel, ModelControlError } from "./local-model.ts";
import { connectLocal } from "./local-asr.ts";

const maxBodyBytes = 128 * 1024;

export type RelayEvent = { type: string; [key: string]: unknown };
export type RelayControls = { emit?: (event: RelayEvent) => void; accepting?: () => boolean };
export function createLiveCueServer(tokenHash: TokenHashes | (() => TokenHashes), runner = new CodexRunner(), controls: RelayControls = {},
  models = new LocalModelController(installedRuntime, status => controls.emit?.({ type: "speech-status", message: status.message })), connect = connectLocal, catalog = modelCatalog) {
  // Warm the last-known-good catalog before the phone sends its first request.
  void catalog().catch(() => {});
  let busy = false;
  let speechActive = () => false;
  const server = createServer(async (request, response) => {
    setSecurityHeaders(response);
    let trackedId: string | undefined;
    const receivedAt = performance.now();
    const expectedHash = typeof tokenHash === "function" ? tokenHash() : tokenHash;
    try {
      authenticate(request, expectedHash);
      controls.emit?.({ type: "phone-seen", time: new Date().toISOString() });
      if (request.method === "GET" && request.url === "/v1/health") {
        return json(response, 200, { ok: true, cloudSpeechReady: Boolean(process.env.LIVECUE_META_API_KEY) });
      }
      if (request.method === "POST" && request.url === "/v1/pair/verify") return json(response, 200, { ok: true });
      if (request.method === "GET" && request.url === "/v1/models") return json(response, 200, { models: await catalog() });
      if (request.method === "GET" && request.url === "/v1/local-model") {
        const status = await models.status();
        return json(response, 200, { ...status, busy: status.busy || speechActive() });
      }
      if (request.method === "POST" && ["/v1/local-model/start", "/v1/local-model/stop"].includes(request.url || "")) {
        if (request.headers.origin || request.headers["sec-fetch-site"]) throw new HttpError(403, "Native app control only.");
        if (controls.accepting?.() === false) throw new HttpError(503, "Resume the PC relay before controlling models.");
        const model = localModel((await readJson(request)).model);
        const status = await models.status();
        if (speechActive() || status.busy) throw new HttpError(409, "Stop the active conversation or lab test before controlling the PC model.");
        if (request.url === "/v1/local-model/stop" && status.model && status.model !== model) throw new HttpError(409, "A different PC model is loaded. Select it before stopping.");
        return json(response, 202, request.url === "/v1/local-model/start" ? models.start(model) : models.stop(model));
      }
      if (request.method === "POST" && (request.url === "/v1/assist" || request.url === "/v1/session-summary")) {
        if (controls.accepting?.() === false) throw new HttpError(503, "PC relay is paused. Resume it in LiveCue Desktop.");
        if (busy) throw new HttpError(429, "The PC is processing another request. Try again shortly.");
        busy = true;
        try {
        const body = await readJson(request);
        const requestReadMs = performance.now() - receivedAt;
        let selection;
        try { selection = validateSelection(body.assistant, await catalog()); }
        catch (error) {
          if (error instanceof CatalogUnavailableError || error instanceof SelectionUnavailableError) throw error;
          throw new HttpError(400, "Invalid assistant settings.");
        }
        const kind = request.url === "/v1/assist" ? "assist" : "summary";
        const requestId = kind === "assist" ? validateRequestId(body) : randomUUID();
        trackedId = requestId;
        const started = performance.now();
        controls.emit?.({ type: "request", requestId, kind, time: new Date().toISOString(), payload: body });
        const answer = await runner.run(requestId, kind, body, 60_000, selection);
        const codexMs = performance.now() - started;
        const relayTotalMs = performance.now() - receivedAt;
        const result = { ...(answer as object), execution: {
          ...selection, codexMs, relayTotalMs, requestReadMs,
          relayOverheadMs: Math.max(0, relayTotalMs - codexMs)
        } };
        controls.emit?.({ type: "reply", requestId, kind, durationMs: relayTotalMs, payload: result });
        return json(response, 200, result);
        } finally { busy = false; }
      }
      const match = /^\/v1\/requests\/([^/]+)$/.exec(request.url || "");
      if (request.method === "DELETE" && match) return json(response, runner.cancel(decodeURIComponent(match[1])) ? 200 : 404, { ok: true });
      json(response, 404, { error: "Endpoint not found." });
    } catch (error: unknown) {
      const catalogError = error instanceof CatalogUnavailableError || error instanceof SelectionUnavailableError;
      const status = error instanceof HttpError || error instanceof ModelControlError || catalogError ? error.status : 500;
      if (catalogError) controls.emit?.({ type: "speech-status", message: error.message });
      if (trackedId) controls.emit?.({ type: "request-error", requestId: trackedId, message: "Assistant request failed or timed out. Check Codex sign-in and retry." });
      json(response, status, { error: status === 500 ? "The local assistant request failed." : (error as Error).message, ...(catalogError ? { code: error.code } : {}) });
    }
  });
  speechActive = attachSpeech(server, tokenHash, controls, undefined, undefined,
    { prepare: model => models.prepare(model), connect }, () => models.changing);
  return server;
}

class HttpError extends Error {
  status: number;
  constructor(status: number, message: string) { super(message); this.status = status; }
}

function authenticate(request: IncomingMessage, expectedHash: TokenHashes): void {
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
