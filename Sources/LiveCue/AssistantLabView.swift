import SwiftUI
import LiveCueCore

struct AssistantLabView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Form {
            Section("PC assistant") {
                Text(model.assistantConfiguration.model).font(.headline).accessibilityIdentifier("selected-assistant-model")
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
                    Picker("Reasoning", selection: $model.assistantConfiguration.reasoningEffort) {
                        ForEach(option.reasoningEfforts, id: \.self) { Text($0.capitalized).tag($0) }
                    }.accessibilityIdentifier("reasoning-picker")
                }
            }.disabled(model.isAssisting)
            Section {
                Button { Task { await model.refreshAssistantModels() } } label: {
                    HStack { Text("Refresh PC model list"); if model.isLoadingModels { ProgressView() } }
                }.disabled(model.isLoadingModels)
                Text(model.modelCatalogMessage).font(.caption).foregroundStyle(.secondary)
                Text("Selection applies to your next Assist and session summary. Low is the lightest reasoning level advertised by this PC. No model is guaranteed to be fastest; test the same text.")
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
                                Text(String(format: "%.2f s total · %.2f s PC Codex", metrics.totalMs / 1000, (metrics.execution?.codexMs ?? 0) / 1000)).font(.caption.monospacedDigit())
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

struct PerformanceView: View {
    let metrics: AssistPerformance
    private func seconds(_ ms: Double) -> String { String(format: "%.3f s", ms / 1000) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Response timing", systemImage: "stopwatch").font(.headline)
            Text("\(metrics.execution?.model ?? metrics.configuration.model) · \(metrics.execution?.reasoningEffort ?? metrics.configuration.reasoningEffort)").font(.caption).textSelection(.enabled)
            LabeledContent("Tap → answer", value: seconds(metrics.totalMs)).fontWeight(.semibold)
            LabeledContent(metrics.reusedText ? "Transcription (reused)" : "Transcription after tap", value: seconds(metrics.transcriptionMs))
            LabeledContent("Build text context", value: seconds(metrics.contextMs))
            LabeledContent("PC round trip", value: seconds(metrics.roundTripMs))
            if let execution = metrics.execution {
                Divider()
                LabeledContent("PC: Codex CLI call", value: seconds(execution.codexMs))
                LabeledContent("PC: relay overhead", value: seconds(execution.relayOverheadMs))
                LabeledContent("Transfer / client estimate", value: seconds(metrics.transportEstimateMs ?? 0))
            } else { Text("PC timing unavailable. Restart the updated desktop relay.").foregroundStyle(.orange) }
            if let chunk = metrics.lastLiveChunkMs { LabeledContent("Last live STT chunk", value: seconds(chunk)) }
            Text("\(metrics.speechModel) · \(metrics.transcriptCharacters) transcript characters\(metrics.reusedText ? " · same-text retry" : "")").font(.caption)
            Text("PC timings are parts of the round trip, not extra time. Codex includes CLI startup, cloud processing and output handling—not pure inference. Transfer is an estimate including encoding/decoding. Parakeet runs before the tap, so its live transcription is not part of tap-to-answer time.")
                .font(.caption).foregroundStyle(.secondary)
        }.font(.subheadline).monospacedDigit().accessibilityIdentifier("response-timing")
    }
}
