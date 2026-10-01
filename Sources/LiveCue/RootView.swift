import SwiftUI
import LiveCueCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if model.activeSession != nil {
                NavigationStack { LiveSessionView() }
            } else {
                TabView {
                    NavigationStack { HomeView() }.tabItem { Label("Live", systemImage: "waveform") }
                    NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "clock") }
                    NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape") }
                }
                .toolbarBackground(MintTheme.background, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
            }
        }
        .tint(MintTheme.mint)
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.checkRelay() } } }
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
}

struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        GeometryReader { geometry in
            if typeSize.isAccessibilitySize {
                ScrollView { content(compact: true) }
            } else {
                content(compact: geometry.size.height < 740)
            }
        }
        .background(MintTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: model.mode) {
            while model.speechProvider.isPCLocal && !Task.isCancelled {
                await model.refreshPCModel()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
    }
    private func content(compact: Bool) -> some View {
        VStack(spacing: compact ? 10 : 14) {
            VStack(spacing: compact ? 5 : 8) {
                VoiceArtwork(level: 0, listening: false, homeIcon: true).frame(height: compact ? 88 : 120)
                Text("LiveCue").font(.system(size: compact ? 30 : 36, weight: .bold))
                Text("A clearer conversation.").font(.system(size: compact ? 17 : 20)).foregroundStyle(.secondary)
                Text((model.mode == "meta" ? "Live captions with Meta Muse." : model.speechProvider.isPCLocal ? "Live captions on your PC's GPU." : "Transcription on your iPhone.") + "\nTap Assist for an answer from " + (model.assistantConfiguration.provider == .codex ? "your PC." : "OpenRouter."))
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Label(!model.needsPC ? (model.speechProvider.isCloud ? "Cloud direct · no PC" : "OpenRouter direct") : model.relayOnline ? "PC online" : model.isPaired ? "PC reconnecting" : "PC offline", systemImage: "circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(!model.needsPC || model.relayOnline ? MintTheme.mint : .orange)
                    .padding(.horizontal, 16).padding(.vertical, 7).background(MintTheme.teal.opacity(0.55), in: Capsule())
            }
            VStack(spacing: 10) {
                HStack {
                    Label("System readiness", systemImage: "checklist").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(model.systemReady ? "✓ Ready" : "Setup")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(MintTheme.mint)
                }
                HStack {
                    Label("Transcription", systemImage: "waveform"); Spacer()
                    Text(model.speechProvider.streamsAudio ? model.speechProvider.name : model.selectedModel?.displayName ?? "Not configured").foregroundStyle(.secondary)
                }.font(.system(size: 13))
                Divider().overlay(MintTheme.mint.opacity(0.08))
                HStack { Label("Windows relay", systemImage: "desktopcomputer"); Spacer(); Text(!model.needsPC ? "Not required" : model.isPaired ? "Paired" : "Pairing required").foregroundStyle(.secondary) }.font(.system(size: 13))
                if model.speechProvider.isCloud {
                    HStack { Label("Meta connection", systemImage: "key.fill"); Spacer(); Text(model.hasMetaKey ? "Key saved · direct" : "Add API key").foregroundStyle(model.hasMetaKey ? MintTheme.mint : .orange) }
                        .font(.system(size: 12)).accessibilityIdentifier("home-meta-state")
                }
                if model.speechProvider.isPCLocal {
                    Divider().overlay(MintTheme.mint.opacity(0.08))
                    HStack(spacing: 7) {
                        Label("PC speech model", systemImage: "cpu")
                        Spacer(minLength: 0)
                        if model.pcModelStatus?.isChanging == true { ProgressView().controlSize(.mini) }
                        Text(model.pcModelHomeLabel)
                            .foregroundStyle(model.pcModelCanStart ? MintTheme.mint : .orange)
                            .monospacedDigit().accessibilityIdentifier("home-pc-model-state")
                    }.font(.system(size: 12))
                }
            }.padding(compact ? 12 : 15).glowPanel()
            VStack(spacing: compact ? 8 : 10) {
                NavigationLink { PairingView() } label: { SetupRow(icon: "desktopcomputer", title: model.isPaired ? "PC connection" : "Pair Windows PC", detail: !model.needsPC ? "Optional for current setup" : model.isPaired ? (model.relayOnline ? "Saved · connected" : "Saved · reconnecting") : "Required", compact: compact) }.accessibilityIdentifier("pair-pc")
                NavigationLink { SettingsView() } label: { SetupRow(icon: "waveform", title: "Transcription & appearance", detail: model.speechProvider.isPCLocal ? model.pcModelHomeLabel : "Cloud, PC or iPhone speech", compact: compact) }.accessibilityIdentifier("transcription-settings")
                NavigationLink { AssistantLabView() } label: { SetupRow(icon: "slider.horizontal.3", title: "Assistant models & timing", detail: model.assistantConfiguration.model.isEmpty ? "Choose an OpenRouter model" : model.assistantConfiguration.model, compact: compact) }.accessibilityIdentifier("assistant-lab")
            }
            Spacer(minLength: 0)
            if !model.speechProvider.streamsAudio && model.selectedModel == nil {
                NavigationLink { ModelLibraryView() } label: { Label("Download a transcription model", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(MintActionStyle()).accessibilityIdentifier("download-model")
            } else {
                Button { Task { await model.startSession() } } label: {
                    HStack { Image(systemName: "record.circle"); Text(model.isTransitioning ? "Connecting…" : "Start conversation"); Spacer(); Image(systemName: "arrow.right") }
                }.buttonStyle(MintActionStyle()).disabled(model.isTransitioning || (model.speechProvider.isPCLocal && !model.pcModelCanStart)).accessibilityIdentifier("start-session")
            }
        }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 12)
    }
}

private struct SetupRow: View {
    let icon: String, title: String, detail: String
    let compact: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22)).foregroundStyle(MintTheme.mint)
                .frame(width: compact ? 38 : 44, height: compact ? 38 : 44)
                .background(MintTheme.teal.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                Text(detail).font(.system(size: 12)).foregroundStyle(Color.gray).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 16)).foregroundStyle(.secondary)
        }.foregroundStyle(.primary).padding(compact ? 10 : 12).glowPanel()
    }
}

struct LiveSessionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showDetails = false
    @State private var showAnswer = false
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 750
            VStack(spacing: 12) {
                VStack(spacing: 3) {
                    Text("LiveCue").font(.system(size: compact ? 28 : 32, weight: .bold))
                    Text("A clearer conversation.").font(.system(size: 15)).foregroundStyle(.secondary)
                }
                VoiceArtwork(level: model.transcriber.energy, listening: model.isRecording && !model.isPaused && !model.isTransitioning)
                    .frame(height: compact ? 88 : 132).accessibilityIdentifier("voice-waveform")
                NavigationLink { AssistantLabView() } label: {
                    HStack {
                        Label(model.assistantConfiguration.model, systemImage: "slider.horizontal.3").font(.system(size: 15))
                        Spacer()
                        Text(model.assistantConfiguration.reasoningEffort).font(.system(size: 13))
                            .padding(.horizontal, 13).padding(.vertical, 6).background(MintTheme.teal.opacity(0.5), in: Capsule())
                    }.frame(minHeight: 36)
                }.accessibilityIdentifier("assistant-lab").disabled(model.isAssisting)
                status
                transcript.frame(maxHeight: .infinity)
                if model.latestAnswer != nil {
                    Button { showAnswer = true } label: {
                        HStack { Label("View assistant answer", systemImage: "sparkles"); Spacer(); Image(systemName: "chevron.up") }.font(.system(size: 14))
                    }.padding(12).glowPanel().accessibilityIdentifier("view-assistant-answer")
                }
                controls
            }.padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 16)
        }
        .background(MintTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showAnswer) { answerSheet.presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .onChange(of: model.latestAnswer?.id) { _, value in if value != nil { showAnswer = true } }
    }
    private var status: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Circle().fill(model.isPaused ? .orange : MintTheme.mint).frame(width: 8, height: 8)
                Text(model.isTransitioning ? "Updating…" : model.isPaused ? "Paused" : "Listening").foregroundStyle(MintTheme.mint)
                Text(model.speechProvider.name).font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(String(format: "%02d:%02d", model.elapsedSeconds / 60, model.elapsedSeconds % 60)).monospacedDigit()
            }.font(.system(size: 16))
            if model.mode == "meta" { HStack {
                Text("Est. transcription")
                Spacer()
                Text((model.activeSession?.transcriptionUsage?.formattedCost ?? "$0.00000") + " USD")
                    .monospacedDigit().accessibilityIdentifier("live-transcription-cost")
            }.font(.system(size: 12)).foregroundStyle(.secondary) }
        }.padding(14).glowPanel(highlight: true)
    }
    private var transcript: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.mode == "voz" ? "TRANSCRIPT" : "LIVE TRANSCRIPT").font(.system(size: 12, weight: .semibold)).tracking(2).foregroundStyle(.secondary)
            if !model.transcriber.timing.isEmpty { Text(model.transcriber.timing).font(.system(size: 12)).foregroundStyle(.secondary) }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if model.activeSession?.segments.isEmpty != false { Text(model.mode == "voz" ? "Recording locally. Tap Assist to transcribe." : "Listening for speech…").foregroundStyle(.secondary) }
                        ForEach(model.activeSession?.segments ?? []) { segment in Text(segment.text).frame(maxWidth: .infinity, alignment: .leading) }
                        if !model.transcriber.partialText.isEmpty { Text(model.transcriber.partialText).foregroundStyle(.secondary) }
                        Color.clear.frame(height: 1).id("transcript-bottom")
                    }.font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("live-transcript")
                .onChange(of: model.activeSession?.segments.count) { _, _ in withAnimation { proxy.scrollTo("transcript-bottom", anchor: .bottom) } }
                .onChange(of: model.transcriber.partialText) { _, _ in proxy.scrollTo("transcript-bottom", anchor: .bottom) }
            }
        }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .glowPanel(highlight: true)
    }
    private var controls: some View {
        HStack(spacing: 16) {
            Button { Task { await model.togglePause() } } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill").frame(width: 54, height: 54)
            }.buttonStyle(MintRoundStyle()).accessibilityLabel(model.isPaused ? "Resume" : "Pause").accessibilityIdentifier("pause-session")
                .disabled(model.isAssisting || model.isTransitioning)
            Button { Task { await model.assist() } } label: {
                HStack { if model.isAssisting { ProgressView() }; Label(model.isAssisting ? model.assistStage : "Assist", systemImage: "sparkles") }.frame(maxWidth: .infinity)
            }.buttonStyle(MintActionStyle()).disabled(model.isAssisting || model.isTransitioning).accessibilityIdentifier("assist-button")
            Button { Task { await model.endSession() } } label: {
                if model.isTransitioning { ProgressView().frame(width: 54, height: 54) }
                else { Image(systemName: "stop.fill").frame(width: 54, height: 54) }
            }.buttonStyle(MintRoundStyle()).disabled(model.isAssisting || model.isTransitioning).accessibilityLabel("Stop conversation").accessibilityIdentifier("end-session")
        }.padding(.top, 3)
    }
    private var answerSheet: some View {
        NavigationStack {
            ScrollView {
                if let answer = model.latestAnswer {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(answer.answer).accessibilityIdentifier("assistant-answer")
                        Button(showDetails ? "Hide detail" : "Expand detail") { showDetails.toggle() }
                        if showDetails { Text(answer.details).foregroundStyle(.secondary) }
                        if let metrics = answer.performance {
                            DisclosureGroup("Timing · " + String(format: "%.2f s total", metrics.totalMs / 1000)) { PerformanceView(metrics: metrics).padding(.top, 8) }.accessibilityIdentifier("timing-disclosure")
                        }
                        Button("Retry same text with selected model") { Task { await model.assist(reuseText: true) } }
                            .disabled(model.isAssisting || model.lastAssistRequest == nil).accessibilityIdentifier("retry-same-text")
                    }.padding(20)
                }
            }.background(MintTheme.background).navigationTitle("Assistant").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAnswer = false }.accessibilityIdentifier("dismiss-answer") } }
        }
    }
}
