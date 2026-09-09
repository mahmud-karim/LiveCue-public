import { readFile } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

export type ModelOption = { id: string; name: string; reasoningEfforts: string[] };
export type ModelSelection = { model: string; reasoningEffort: string };
export const defaultSelection: ModelSelection = { model: "gpt-5.6-sol", reasoningEffort: "low" };
const efforts = new Set(["low", "medium", "high", "xhigh", "max"]);
export async function modelCatalog(): Promise<ModelOption[]> {
  try {
    const cache = JSON.parse(await readFile(join(process.env.CODEX_HOME || join(homedir(), ".codex"), "models_cache.json"), "utf8"));
    const models: ModelOption[] = (cache.models || [])
      .filter((m: any) => m.visibility === "list" && /^gpt-[a-z0-9.-]+$/.test(m.slug))
      .map((m: any) => ({ id: m.slug, name: String(m.display_name || m.slug),
        reasoningEfforts: (m.supported_reasoning_levels || []).map((e: any) => e.effort).filter((e: string) => efforts.has(e)) }))
      .filter((m: ModelOption) => m.reasoningEfforts.length);
    if (models.length) return models;
  } catch { /* Offline/first-run fallback, not an account-access guarantee. */ }
  return [{ id: defaultSelection.model, name: "GPT-5.6 Sol", reasoningEfforts: ["low"] }];
}
export function validateSelection(value: unknown, catalog: ModelOption[]): ModelSelection {
  if (value === undefined) return { ...defaultSelection };
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid assistant settings.");
  const selection = value as ModelSelection;
  const model = catalog.find(m => m.id === selection.model);
  if (!model || !model.reasoningEfforts.includes(selection.reasoningEffort)) {
    throw new Error("Model or reasoning level is unavailable. Refresh the PC model list.");
  }
  return { model: selection.model, reasoningEffort: selection.reasoningEffort };
}
