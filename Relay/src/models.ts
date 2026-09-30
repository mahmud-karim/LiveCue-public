import { CurrentCatalogSource } from "./codex-catalog.ts";

export type ModelOption = { id: string; name: string; reasoningEfforts: string[] };
export type ModelSelection = { model: string; reasoningEffort: string };
export const defaultSelection: ModelSelection = { model: "gpt-5.6-sol", reasoningEffort: "low" };
const efforts = new Set(["none", "minimal", "low", "medium", "high", "xhigh", "max"]);
// These support no-reasoning requests even when the CLI picker cache omits it.
// Verified with signed-in CLI + LiveCue's structured output on 2026-09-09.
const noReasoningModels = new Set(["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"]);
export function supportedEfforts(model: string, advertised: string[]): string[] {
  const values = advertised.filter(e => efforts.has(e));
  return [...new Set(noReasoningModels.has(model) ? ["none", ...values] : values)];
}
export class CatalogUnavailableError extends Error {
  status = 503;
  code = "ASSISTANT_CATALOG_UNAVAILABLE";
  constructor() { super("The PC could not read Codex's model list. Keep Codex signed in, then retry. Your selected model has not changed."); }
}
export class SelectionUnavailableError extends Error {
  status = 400;
  code = "ASSISTANT_SELECTION_UNAVAILABLE";
  constructor() { super("The selected assistant model or reasoning level is not in this PC's current Codex catalog. Open Assistant models & timing and choose an available combination."); }
}

// Codex can replace its cache while a request is reading it. A failed read must
// not invent a smaller catalog and reject a model we just offered to the phone.
export class ModelCatalogReader {
  private lastGood: ModelOption[] | undefined;
  private load: () => Promise<string>;
  constructor(load: () => Promise<string>) { this.load = load; }
  async read(): Promise<ModelOption[]> {
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const cache = JSON.parse(await this.load());
        if (!Array.isArray(cache.models)) throw new Error("Invalid catalog");
        const models: ModelOption[] = cache.models
          .filter((m: any) => m && m.visibility === "list" && /^gpt-[a-z0-9.-]+$/.test(m.slug))
          .map((m: any) => ({ id: m.slug, name: String(m.display_name || m.slug),
            reasoningEfforts: supportedEfforts(m.slug, (m.supported_reasoning_levels || []).map((e: any) => e.effort)) }))
          .filter((m: ModelOption) => m.reasoningEfforts.length);
        this.lastGood = models;
        return structuredClone(models);
      } catch {
        if (attempt < 2) await new Promise(resolve => setTimeout(resolve, 50));
      }
    }
    if (this.lastGood) return structuredClone(this.lastGood);
    throw new CatalogUnavailableError();
  }
}
const source = new CurrentCatalogSource();
const reader = new ModelCatalogReader(() => source.read());
export const modelCatalog = () => reader.read();
export function validateSelection(value: unknown, catalog: ModelOption[]): ModelSelection {
  if (value === undefined) value = { ...defaultSelection };
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid assistant settings.");
  const selection = value as ModelSelection;
  const model = catalog.find(m => m.id === selection.model);
  if (!model || !model.reasoningEfforts.includes(selection.reasoningEffort)) {
    throw new SelectionUnavailableError();
  }
  return { model: selection.model, reasoningEffort: selection.reasoningEffort };
}
