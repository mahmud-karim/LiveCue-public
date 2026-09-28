import SwiftUI
import LiveCueCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            modePage.tabItem { Label("Live", systemImage: "waveform") }
            NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "clock") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(MintTheme.mint)
        .toolbarBackground(MintTheme.background, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task {
            while !Task.isCancelled {
                await model.checkRelay()
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
            }
        }
        .alert("LiveCue", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var modePage: some View {
        NavigationStack {
            Group {
                if model.activeSession != nil { LiveSessionView() }
                else { HomeView() }
            }
            .background(MintTheme.background)
            .navigationTitle("LiveCue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { Text("LiveCue").font(.system(size: 22, weight: .semibold)) } }
            .toolbarBackground(MintTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct StatusPill: View {
    let online: Bool
    var body: some View {
        Label(online ? "PC online" : "PC offline", systemImage: online ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.caption.weight(.semibold)).foregroundStyle(online ? .green : .orange)
            .padding(.horizontal, 10).padding(.vertical, 6).background(.thinMaterial, in: Capsule())
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 10) {
                    Image(systemName: "waveform").font(.system(size: 36)).foregroundStyle(MintTheme.mint).padding(16).background(MintTheme.teal, in: RoundedRectangle(cornerRadius: 20))
                    Text(model.mode == "voz" ? "Record. Assist. Answer." : "A clearer conversation.").font(.system(size: 22, weight: .semibold))
                    Text(model.mode == "meta" ? "Live captions with Meta Muse. Tap Assist when you want a reply from your PC." : (model.mode == "voz" ? "Voz transcribes locally when you tap Assist. Only text goes to your PC." : "Parakeet transcribes live on your iPhone. Only text goes to your PC."))
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    StatusPill(online: model.relayOnline)
                }.padding(.vertical, 18)

                if model.mode != "meta" && model.selectedModel == nil {
                    NavigationLink { ModelLibraryView() } label: {
                        Label("Download a transcription model", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("download-model")
                } else {
                    Button { Task { await model.startSession() } } label: {
                        Label("Start conversation", systemImage: "record.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).foregroundStyle(MintTheme.background).controlSize(.large).disabled(model.isTransitioning).accessibilityIdentifier("start-session")
                }

                GroupBox {
                    LabeledContent("Transcription", value: model.mode == "meta" ? "Meta Muse · cloud" : model.selectedModel?.displayName ?? "Not configured")
                    Divider()
                    LabeledContent("Windows relay", value: model.isPaired ? "Paired" : "Pairing required")
                } label: { Label("Readiness", systemImage: "checklist") }

                NavigationLink { PairingView() } label: { SettingsRow(icon: "desktopcomputer", title: "Pair Windows PC", detail: model.isPaired ? "Configured" : "Required") }.accessibilityIdentifier("pair-pc")
                NavigationLink { SettingsView() } label: { SettingsRow(icon: "waveform", title: "Transcription & appearance", detail: "Cloud or on-device speech") }
                NavigationLink { AssistantLabView() } label: { SettingsRow(icon: "slider.horizontal.3", title: "Assistant models & timing", detail: model.assistantConfiguration.model) }.accessibilityIdentifier("assistant-lab")
                if model.mode == "meta" { Text("Audio is processed by Meta via your PC. Cloud usage is billed to your Meta account.").font(.system(size: 13)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding()
        }
        .refreshable { await model.checkRelay() }
    }
}

private struct SettingsRow: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack { Image(systemName: icon).frame(width: 30).foregroundStyle(MintTheme.mint); VStack(alignment: .leading, spacing: 5) { Text(title); Text(detail).font(.system(size: 13)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        .padding(14).background(MintTheme.card, in: RoundedRectangle(cornerRadius: 14)).foregroundStyle(.primary)
    }
}

struct LiveSessionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDetails = false
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    NavigationLink { AssistantLabView() } label: {
                        HStack { Label(model.assistantConfiguration.model, systemImage: "slider.horizontal.3"); Spacer(); Text(model.assistantConfiguration.reasoningEffort).font(.caption) }
                    }.accessibilityIdentifier("assistant-lab").disabled(model.isAssisting)
                    HStack {
                        Circle().fill(model.isPaused ? .orange : MintTheme.mint).frame(width: 8)
                        Text(model.isPaused ? "Paused" : "Listening").foregroundStyle(MintTheme.mint)
                        Text(model.mode == "meta" ? "Muse Voice" : model.mode.capitalized).font(.system(size: 13)).foregroundStyle(.secondary)
                        Spacer()
                        Text(duration(model.elapsedSeconds)).monospacedDigit()
                        AudioMeter(level: model.transcriber.energy)
                    }.padding(14).background(MintTheme.card, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.mode == "voz" ? "TRANSCRIPT" : "LIVE TRANSCRIPT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if !model.transcriber.timing.isEmpty { Text(model.transcriber.timing).font(.caption).foregroundStyle(.secondary) }
                        if model.activeSession?.segments.isEmpty != false { Text(model.mode == "voz" ? "Recording locally. Tap Assist to transcribe." : "Listening for speech…").foregroundStyle(.secondary) }
                        ForEach(model.activeSession?.segments ?? []) { segment in Text(segment.text).frame(maxWidth: .infinity, alignment: .leading) }
                        if !model.transcriber.partialText.isEmpty { Text(model.transcriber.partialText).foregroundStyle(.secondary).italic() }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(MintTheme.card, in: RoundedRectangle(cornerRadius: 16))

                    if let answer = model.latestAnswer {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("ASSISTANT", systemImage: "sparkles").font(.system(size: 12, weight: .semibold)).foregroundStyle(MintTheme.mint)
                            Text(answer.answer).accessibilityIdentifier("assistant-answer")
                            if showDetails { Divider(); Text(answer.details).foregroundStyle(.secondary) }
                            Button(showDetails ? "Hide detail" : "Expand detail") { showDetails.toggle() }
                            if let metrics = answer.performance {
                                DisclosureGroup("Timing · " + String(format: "%.2f s total", metrics.totalMs / 1000)) {
                                    PerformanceView(metrics: metrics).padding(.top, 8)
                                }.accessibilityIdentifier("timing-disclosure")
                            }
                            Button("Retry same text with selected model") { Task { await model.assist(reuseText: true) } }
                                .disabled(model.isAssisting || model.lastAssistRequest == nil).accessibilityIdentifier("retry-same-text")
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(MintTheme.teal.opacity(0.65), in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(MintTheme.mint.opacity(0.4)))
                    }
                }.padding()
            }
            .onChange(of: model.activeSession?.segments.count) { _, _ in withAnimation { proxy.scrollTo("bottom") } }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 10) {
                TextField("Optional instruction (e.g. answer briefly)", text: $model.instruction).textFieldStyle(.roundedBorder)
                HStack {
                    Button { Task { await model.togglePause() } } label: { Image(systemName: model.isPaused ? "play.fill" : "pause.fill").frame(width: 42, height: 42) }.buttonStyle(.bordered).disabled(model.isAssisting || model.isTransitioning)
                    Button { Task { await model.assist() } } label: {
                        if model.isAssisting { HStack { ProgressView(); Text(model.assistStage) }.frame(maxWidth: .infinity) }
                        else { Label("Assist", systemImage: "sparkles").frame(maxWidth: .infinity) }
                    }.buttonStyle(.borderedProminent).foregroundStyle(MintTheme.background).controlSize(.large).disabled(model.isAssisting || model.isTransitioning).accessibilityIdentifier("assist-button")
                    Button(role: .destructive) { Task { await model.endSession() } } label: { Image(systemName: "stop.fill").frame(width: 42, height: 42) }.buttonStyle(.bordered).disabled(model.isAssisting || model.isTransitioning).accessibilityIdentifier("end-session")
                }
            }.padding().background(.ultraThinMaterial)
        }
    }
    private func duration(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
}

private struct AudioMeter: View {
    let level: Float
    var body: some View { HStack(spacing: 2) { ForEach(0..<4) { index in Capsule().fill(Float(index) / 4 < min(1, abs(level) * 10) ? .green : .gray.opacity(0.3)).frame(width: 3, height: CGFloat(8 + index * 4)) } } }
}
