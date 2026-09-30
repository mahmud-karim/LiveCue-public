import SwiftUI
import LiveCueCore

struct AssistantLabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyInput = ""
    @FocusState private var keyFocused: Bool
    var body: some View {
        Form {
            Section("Answer service") {
                NavigationLink {
                    List(AssistantProvider.allCases, id: \.self) { provider in
                        Button { model.selectAssistantProvider(provider); Task { await model.refreshAssistantModels() } } label: {
                            HStack { Text(provider.name); Spacer(); if model.assistantConfiguration.provider == provider { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("assistant-provider-" + provider.rawValue)
                    }.navigationTitle("Answer service")
                } label: { LabeledContent("Provider", value: model.assistantConfiguration.provider.name) }
                .accessibilityIdentifier("assistant-provider").disabled(model.isAssisting)
            }
            if model.assistantConfiguration.provider == .openrouter {
                Section("OpenRouter API key") {
                    SecureField("Paste API key", text: $keyInput).textInputAutocapitalization(.never).autocorrectionDisabled().focused($keyFocused).accessibilityIdentifier("openrouter-key")
                    Button("Save key") { if model.saveOpenRouterKey(keyInput) { keyInput = ""; keyFocused = false } }.disabled(keyInput.isEmpty).accessibilityIdentifier("save-openrouter-key")
                    Text(model.hasOpenRouterKey ? "Key saved" : "No key saved").accessibilityIdentifier("openrouter-key-state")
                    if model.hasOpenRouterKey {
                        Button("Verify key (no inference)") { Task { await model.verifyOpenRouterKey() } }.disabled(model.isVerifyingOpenRouterKey).accessibilityIdentifier("verify-openrouter-key")
                        Button("Remove key", role: .destructive) { model.removeOpenRouterKey() }.accessibilityIdentifier("remove-openrouter-key")
                    }
                    Text(model.openRouterKeyMessage).font(.caption)
                    Link("Get an OpenRouter API key", destination: URL(string: "https://openrouter.ai/keys")!)
                    Text("Stored only in this iPhone's Keychain and sent directly to OpenRouter—not your PC or GitHub. Each Assist sends transcript context and can incur API charges. Stop does not make another paid request. PC speech models still need the PC; on-iPhone transcription does not.").font(.caption).foregroundStyle(.secondary)
                }.disabled(model.isAssisting)
            }
            Section(model.assistantConfiguration.provider == .codex ? "PC assistant" : "OpenRouter assistant") {
                Text(model.assistantConfiguration.model).font(.headline).accessibilityIdentifier("selected-assistant-model")
                if model.assistantConfiguration.provider == .openrouter {
                    NavigationLink { OpenRouterModelPicker() } label: { Text(model.assistantConfiguration.model.isEmpty ? "Choose a model" : "Change model") }.accessibilityIdentifier("openrouter-model-picker")
                    Text("Uses the selected model's default reasoning behavior.").font(.caption).foregroundStyle(.secondary)
                } else {
                  Text("Reasoning: " + model.assistantConfiguration.reasoningEffort).foregroundStyle(.secondary)
                  ForEach(model.assistantModels) { option in
                    Button {
                        let effort = option.reasoningEfforts.contains(model.assistantConfiguration.reasoningEffort) ? model.assistantConfiguration.reasoningEffort : (option.reasoningEfforts.first ?? "low")
                        model.assistantConfiguration = .init(model: option.id, reasoningEffort: effort)
                    } label: {
                        HStack { Text(option.name); Spacer(); if option.id == model.assistantConfiguration.model { Image(systemName: "checkmark") } }
                    }.accessibilityIdentifier("choose-" + option.id)
                }
                if let option = model.assistantModels.first(where: { $0.id == model.assistantConfiguration.model }) {
                    NavigationLink { ReasoningSelectionView(efforts: option.reasoningEfforts) } label: {
                        LabeledContent("Reasoning", value: model.assistantConfiguration.reasoningEffort.capitalized)
                    }.accessibilityIdentifier("reasoning-picker")
                }
                }
            }.disabled(model.isAssisting)
            Section {
                Button { Task { await model.refreshAssistantModels() } } label: {
                    HStack { Text(model.assistantConfiguration.provider == .codex ? "Refresh PC model list" : "Refresh OpenRouter models"); if model.isLoadingModels { ProgressView() } }
                }.disabled(model.isLoadingModels)
                Text(model.modelCatalogMessage).font(.caption).foregroundStyle(.secondary)
                Text(model.assistantConfiguration.provider == .codex ? "Selection applies to your next Assist and session summary. None disables reasoning on supported models; it does not remove network or CLI startup time. Astra and Spark start at Low. No model is guaranteed to be fastest; test the same text." : "Answers bypass the PC and Codex CLI. Models may differ in availability and price. There are no automatic paid retries or fallback models.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Recent comparisons") {
                if model.comparisonTurns.isEmpty { Text("Assist once to start collecting results.").foregroundStyle(.secondary) }
                ForEach(Array(model.comparisonTurns.prefix(50))) { turn in
                    if let metrics = turn.performance {
                        NavigationLink {
                            ScrollView { VStack(alignment: .leading, spacing: 20) {
                                Text(turn.detectedQuestion).font(.headline)
                                Text(turn.answer)
                                PerformanceView(metrics: metrics)
                            }.padding() }.navigationTitle("Run details")
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(metrics.execution?.model ?? metrics.configuration.model).font(.headline)
                                Text("\(metrics.speechModel) · \(metrics.configuration.reasoningEffort) · \(metrics.reusedText ? "same text" : "fresh transcript")").font(.caption)
                                Text(String(format: "%.2f s total", metrics.totalMs / 1000) + " · " + metrics.configuration.provider.name).font(.caption.monospacedDigit())
                                Text(turn.detectedQuestion).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
            }
        }.navigationTitle("Assistant Lab")
        .task { await model.refreshAssistantModels() }
    }
}

private struct OpenRouterModelPicker: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var options: [AssistantModelOption] {
        model.assistantModels.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) }
    }
    private func price(_ raw: String?) -> String {
        guard let raw, let amount = Double(raw), amount.isFinite, amount >= 0 else { return "Unknown" }
        return String(format: "$%.3f / 1M", amount * 1_000_000)
    }
    var body: some View {
        List(options) { option in
            Button {
                model.assistantConfiguration = .init(model: option.id, reasoningEffort: "default", provider: .openrouter); dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(option.name); Spacer(); if option.id == model.assistantConfiguration.model { Image(systemName: "checkmark") } }
                    Text(option.id).font(.caption).foregroundStyle(.secondary)
                    Text("Input " + price(option.promptPrice) + " · output " + price(option.completionPrice)).font(.caption2).foregroundStyle(.secondary)
                }
            }.accessibilityIdentifier("choose-" + option.id)
        }.searchable(text: $search).navigationTitle("OpenRouter models")
        .overlay { if options.isEmpty { ContentUnavailableView("No models", systemImage: "magnifyingglass", description: Text("Refresh the catalog or change your search.")) } }
    }
}

private struct ReasoningSelectionView: View {
    let efforts: [String]
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        List(efforts, id: \.self) { effort in
            Button {
                model.assistantConfiguration.reasoningEffort = effort; dismiss()
            } label: {
                HStack { Text(effort == "none" ? "None (no reasoning)" : effort.capitalized); Spacer(); if effort == model.assistantConfiguration.reasoningEffort { Image(systemName: "checkmark") } }
            }.accessibilityIdentifier("effort-" + effort)
        }.navigationTitle("Reasoning").navigationBarTitleDisplayMode(.inline)
    }
}

struct PerformanceView: View {
    let metrics: AssistPerformance
    private func seconds(_ ms: Double) -> String { String(format: "%.3f s", ms / 1000) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Response timing", systemImage: "stopwatch").font(.headline)
            Text("\(metrics.execution?.model ?? metrics.configuration.model) · \(metrics.execution?.reasoningEffort ?? metrics.configuration.reasoningEffort)").font(.caption).textSelection(.enabled)
            LabeledContent("Tap → answer", value: seconds(metrics.totalMs)).fontWeight(.semibold)
            LabeledContent(metrics.reusedText ? "Transcription (reused)" : "Transcription after tap", value: seconds(metrics.transcriptionMs))
            LabeledContent("Context + model check", value: seconds(metrics.contextMs))
            LabeledContent(metrics.configuration.provider == .codex ? "PC round trip" : "OpenRouter round trip", value: seconds(metrics.roundTripMs))
            if metrics.configuration.provider == .openrouter {
                LabeledContent("Reported request cost", value: metrics.execution?.usage?.costCredits.map { String(format: "%.6f credits", $0) } ?? "Unavailable")
                if let usage = metrics.execution?.usage { Text("\(usage.promptTokens ?? 0) input · \(usage.completionTokens ?? 0) output tokens").font(.caption) }
            } else if let execution = metrics.execution {
                Divider()
                LabeledContent("PC: Codex CLI call", value: seconds(execution.codexMs))
                LabeledContent("PC: relay overhead", value: seconds(execution.relayOverheadMs))
                LabeledContent("Transfer / client estimate", value: seconds(metrics.transportEstimateMs ?? 0))
            } else { Text("PC timing unavailable. Restart the updated desktop relay.").foregroundStyle(.orange) }
            if let chunk = metrics.lastLiveChunkMs { LabeledContent("Last live STT chunk", value: seconds(chunk)) }
            Text("\(metrics.speechModel) · \(metrics.transcriptCharacters) transcript characters\(metrics.reusedText ? " · same-text retry" : "")").font(.caption)
            Text(metrics.configuration.provider == .codex ? "PC timings are parts of the round trip, not extra time. Codex includes CLI startup, cloud processing and output handling—not pure inference. Transfer is an estimate including encoding/decoding. Live transcription runs before the tap, so it is not part of tap-to-answer time." : "OpenRouter round trip includes network, provider processing and response decoding—not pure inference. Cost is reported by OpenRouter after the request; missing cost is not treated as free. Speech transcription is a separate service.")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.subheadline).monospacedDigit().accessibilityIdentifier("response-timing")
    }
}
