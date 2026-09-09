import SwiftUI
import LiveCueCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: Binding(get: { model.mode }, set: { newMode in
            guard newMode != model.mode else { return }
            guard model.activeSession == nil, !model.isPreparing else {
                model.errorMessage = "Finish the current session or model preparation before switching tabs."; return
            }
            model.mode = newMode
        })) {
            modePage.tabItem { Label("Voz on Assist", systemImage: "sparkles") }.tag("voz")
            modePage.tabItem { Label("Live Parakeet", systemImage: "waveform") }.tag("parakeet")
        }
        .tint(.indigo)
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
            .navigationTitle(model.mode == "voz" ? "Voz on Assist" : "Live Parakeet")
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
                    Image(systemName: "waveform.and.mic").font(.system(size: 54)).foregroundStyle(.indigo)
                    Text(model.mode == "voz" ? "Record. Tap Assist. Get an answer." : "See the conversation as you speak.").font(.title2.bold())
                    Text(model.mode == "voz" ? "Voz transcribes your recorded audio on this iPhone when you tap Assist. Only text is sent to your PC." : "Parakeet transcribes continuously on this iPhone. Tap Assist to send the current text to your PC.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    StatusPill(online: model.relayOnline)
                }.padding(.vertical, 18)

                if model.selectedModel == nil {
                    NavigationLink { ModelLibraryView() } label: {
                        Label("Download a transcription model", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("download-model")
                } else {
                    Button { Task { await model.startSession() } } label: {
                        Label("Start conversation", systemImage: "record.circle").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("start-session")
                }

                GroupBox {
                    LabeledContent("Transcription", value: model.selectedModel?.displayName ?? "Not configured")
                    Divider()
                    LabeledContent("Windows relay", value: model.isPaired ? "Paired" : "Pairing required")
                } label: { Label("Readiness", systemImage: "checklist") }

                NavigationLink { PairingView() } label: { SettingsRow(icon: "desktopcomputer", title: "Pair Windows PC", detail: model.isPaired ? "Configured" : "Required") }.accessibilityIdentifier("pair-pc")
                NavigationLink { ModelLibraryView() } label: { SettingsRow(icon: "cpu", title: "Model Library", detail: "On-device speech models") }
                NavigationLink { ModelLabView() } label: { SettingsRow(icon: "gauge.with.dots.needle.67percent", title: "Model Lab", detail: "Speed and accuracy benchmark") }
                NavigationLink { AssistantLabView() } label: { SettingsRow(icon: "slider.horizontal.3", title: "Assistant models & timing", detail: model.assistantConfiguration.model) }.accessibilityIdentifier("assistant-lab")
                NavigationLink { HistoryView() } label: { SettingsRow(icon: "clock.arrow.circlepath", title: "History", detail: "\(model.sessions.count) saved sessions") }
            }.padding()
        }
        .refreshable { await model.checkRelay() }
    }
}

private struct SettingsRow: View {
    let icon: String, title: String, detail: String
    var body: some View {
        HStack { Image(systemName: icon).frame(width: 30).foregroundStyle(.indigo); VStack(alignment: .leading) { Text(title).font(.headline); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        .padding().background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16)).foregroundStyle(.primary)
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
                        Circle().fill(model.isPaused ? .orange : .red).frame(width: 10)
                        Text(model.isPaused ? "Paused" : "Recording").font(.headline)
                        Spacer()
                        Text(duration(model.elapsedSeconds)).monospacedDigit()
                        AudioMeter(level: model.transcriber.energy)
                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(model.mode == "voz" ? "TRANSCRIPT" : "LIVE TRANSCRIPT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if !model.transcriber.timing.isEmpty { Text(model.transcriber.timing).font(.caption).foregroundStyle(.secondary) }
                        if model.activeSession?.segments.isEmpty != false { Text(model.mode == "voz" ? "Recording locally. Tap Assist to transcribe." : "Listening for speech…").foregroundStyle(.secondary) }
                        ForEach(model.activeSession?.segments ?? []) { segment in Text(segment.text).frame(maxWidth: .infinity, alignment: .leading) }
                        if !model.transcriber.partialText.isEmpty { Text(model.transcriber.partialText).foregroundStyle(.secondary).italic() }
                        Color.clear.frame(height: 1).id("bottom")
                    }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                    if let answer = model.latestAnswer {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("ASSISTANT", systemImage: "sparkles").font(.caption.bold()).foregroundStyle(.indigo)
                            Text(answer.answer).font(.title3.weight(.semibold)).accessibilityIdentifier("assistant-answer")
                            if showDetails { Divider(); Text(answer.details).foregroundStyle(.secondary) }
                            Button(showDetails ? "Hide detail" : "Expand detail") { showDetails.toggle() }
                            if let metrics = answer.performance {
                                DisclosureGroup("Timing · " + String(format: "%.2f s total", metrics.totalMs / 1000)) {
                                    PerformanceView(metrics: metrics).padding(.top, 8)
                                }.accessibilityIdentifier("timing-disclosure")
                            }
                            Button("Retry same text with selected model") { Task { await model.assist(reuseText: true) } }
                                .disabled(model.isAssisting || model.lastAssistRequest == nil).accessibilityIdentifier("retry-same-text")
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
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
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(model.isAssisting || model.isTransitioning).accessibilityIdentifier("assist-button")
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
