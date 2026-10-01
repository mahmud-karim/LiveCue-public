import SwiftUI

enum MintTheme {
    static let background = Color(red: 0.043, green: 0.078, blue: 0.078)
    static let card = Color(red: 0.072, green: 0.130, blue: 0.139)
    static let mint = Color(red: 0.180, green: 0.902, blue: 0.714)
    static let teal = Color(red: 0.055, green: 0.239, blue: 0.227)
}

struct MintTypography: ViewModifier {
    @ScaledMetric(relativeTo: .body) private var size = 16.0
    func body(content: Content) -> some View { content.font(.system(size: size)).tint(MintTheme.mint).preferredColorScheme(.dark) }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var editingInstruction: Bool
    var body: some View {
        Form {
            Section("Transcription & AI") {
                NavigationLink { SpeechProviderView() } label: {
                    LabeledContent("Transcription", value: model.speechProvider.name)
                }.disabled(model.activeSession != nil || model.isPreparing || model.isControllingPCModel || model.pcModelStatus?.isChanging == true).accessibilityIdentifier("speech-provider")
                if !model.speechProvider.streamsAudio {
                    NavigationLink("Model Library") { ModelLibraryView() }
                    NavigationLink("Speech benchmark") { ModelLabView() }
                }
                NavigationLink { AssistantLabView() } label: { Label("Assistant models & timing", systemImage: "slider.horizontal.3") }.accessibilityIdentifier("assistant-lab")
                Text(model.mode == "meta" ? "Audio streams directly from this iPhone to Meta. No PC or model download. Cloud usage is billed by Meta. Recording stops if the connection fails; resume to reconnect." : model.speechProvider.isPCLocal ? "Audio streams to the model on your PC's GPU. No speech API charges. Keep Docker Desktop and LiveCue Desktop running. Switching models may take a minute; recording starts only when ready." : "Audio is transcribed on this iPhone. Only text is sent to " + (model.assistantConfiguration.provider == .codex ? "your PC." : "OpenRouter when you tap Assist.")).font(.system(size: 13)).foregroundStyle(.secondary)
                if model.speechProvider.isCloud {
                    NavigationLink { MetaKeyView() } label: { LabeledContent("Meta API key", value: model.hasMetaKey ? "Saved on iPhone" : "Required") }.accessibilityIdentifier("meta-key-settings")
                }
            }
            if model.speechProvider.isPCLocal { PCModelControls() }
            Section("Assistant instructions") {
                TextField("Optional instruction (e.g. answer briefly)", text: $model.instruction, axis: .vertical)
                    .lineLimit(2...5).accessibilityIdentifier("assistant-instruction")
                    .focused($editingInstruction)
                Text("Applied to every Assist request until you change it.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Transcription cost") {
                LabeledContent("Meta Muse rate", value: "$0.18 / hour")
                LabeledContent("PC-local models", value: "$0 API usage")
                Text("Live estimates use audio sent; completed streams use Meta's reported processed audio, rounded down to whole seconds per stream. Silence sent to Meta counts as audio. Credits and billing adjustments are not included. Interrupted streams may have incomplete usage. This estimates transcription only, not assistant usage.").font(.caption).foregroundStyle(.secondary)
                Link("Meta pricing & usage documentation", destination: URL(string: "https://dev.meta.ai/docs/speech-to-text#pricing")!)
            }
            Section("Display") {
                LabeledContent("Text size", value: "16 pt · follows Dynamic Type")
                LabeledContent("Appearance", value: "Midnight Mint")
                LabeledContent("Version", value: (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.5.1")
            }
            Section("Devices") {
                NavigationLink { PairingView() } label: { Label("Pair Windows PC", systemImage: "desktopcomputer") }.accessibilityIdentifier("pair-pc")
            }
            Section("Privacy") {
                Text("Meta and OpenRouter API keys stay in this iPhone's Keychain and go only to their respective services. Cloud audio goes directly to Meta; cloud Assist text goes directly to OpenRouter. PC-local speech and Codex Assist still use your paired PC. Transcripts and replies are saved in iPhone history. Obtain permission before recording others.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden).background(MintTheme.background).navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { editingInstruction = false }.accessibilityIdentifier("finish-instruction")
                }
            }
    }
}

private struct PCModelControls: View {
    @EnvironmentObject private var model: AppModel
    private var changing: Bool { model.isControllingPCModel || model.pcModelStatus?.isChanging == true }
    private var locked: Bool { changing || model.activeSession != nil || model.pcModelStatus?.busy == true || !model.isPaired }
    var body: some View {
        Section("PC model controls") {
            HStack {
                if changing { ProgressView().tint(MintTheme.mint) }
                Text(model.pcModelStatus?.state.capitalized ?? "Unavailable").foregroundStyle(model.pcModelReady ? MintTheme.mint : .secondary)
                    .accessibilityIdentifier("pc-model-state")
                Spacer()
                if let status = model.pcModelStatus, status.isChanging { Text("\(status.elapsedSeconds) s").monospacedDigit() }
            }
            if let loaded = model.pcModelStatus?.model, loaded != model.mode {
                Text("Currently loaded: \(loaded). Start switches to your selected model when it is idle.").font(.caption).foregroundStyle(.secondary)
            }
            Text(model.pcModelMessage).font(.callout).foregroundStyle(.secondary).accessibilityIdentifier("pc-model-message")
            HStack(spacing: 16) {
                Button { Task { await model.controlPCModel(start: true) } } label: { Label("Start model", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent).disabled(locked || model.pcModelReady).accessibilityIdentifier("start-pc-model")
                Button { Task { await model.controlPCModel(start: false) } } label: { Label("Stop model", systemImage: "stop.fill") }
                    .buttonStyle(.bordered).disabled(locked || model.pcModelStatus == nil || model.pcModelStatus?.state == "stopped" || model.pcModelStatus?.model != model.mode).accessibilityIdentifier("stop-pc-model")
            }
            Button("Refresh status") { Task { await model.refreshPCModel() } }.accessibilityIdentifier("refresh-pc-model")
            Text(model.activeSession != nil ? "End the conversation before starting or unloading a model." : "Start opens Docker Desktop if needed. Stop unloads only LiveCue’s speech model; weights stay installed and Docker remains open. One PC model runs at a time.").font(.caption).foregroundStyle(.secondary)
        }
        .task(id: model.mode) {
            while !Task.isCancelled {
                await model.refreshPCModel()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

private struct SpeechProviderView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let options = [("meta", "Meta Muse · live cloud"), ("nemotron", "Nemotron 3.5 · PC live"), ("qwen3", "Qwen3 1.7B · PC live"), ("voz", "Voz · iPhone on Assist"), ("parakeet", "Parakeet · iPhone live")]
    var body: some View {
        List {
            ForEach(options, id: \.0) { option in
                Button { model.mode = option.0; dismiss() } label: {
                    HStack { Text(option.1); Spacer(); if model.mode == option.0 { Image(systemName: "checkmark") } }
                }.accessibilityIdentifier("provider-" + option.0)
            }
            Text("PC models run one at a time on your GPU. Start a new conversation to compare them. Neither sends audio to Meta.").font(.caption).foregroundStyle(.secondary)
        }.navigationTitle("Transcription").navigationBarTitleDisplayMode(.inline)
    }
}
