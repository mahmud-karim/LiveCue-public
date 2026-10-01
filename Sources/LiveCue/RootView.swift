import SwiftUI
import UIKit
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
    @State private var expandTranscript = false
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(MintTheme.mint)
                    Text("LiveCue").font(.system(size: 20, weight: .semibold))
                    Spacer()
                    NavigationLink { AssistantLabView() } label: {
                        Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44)
                    }.accessibilityLabel("Assistant models & timing").accessibilityIdentifier("assistant-lab").disabled(model.isAssisting)
                }
                status
                transcriptPeek(maxHeight: min(180, geometry.size.height * 0.24))
                answerFeed.frame(maxHeight: .infinity)
                controls
            }.padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(MintTheme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
    private var status: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Circle().fill(model.isPaused ? .orange : MintTheme.mint).frame(width: 7, height: 7)
                Text(model.isTransitioning ? "Updating…" : model.isPaused ? "Paused" : "Listening")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(MintTheme.mint)
                // Audio-reactive but only 32 points wide; the answer gets the space.
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<5) { index in
                        Capsule().fill(MintTheme.mint.opacity(0.8))
                            .frame(width: 3, height: model.isPaused ? 4 : 4 + CGFloat(min(1, max(0, model.transcriber.energy * 12))) * CGFloat([10, 16, 22, 14, 8][index]))
                    }
                }.frame(width: 26, height: 22).animation(.easeOut(duration: 0.12), value: model.transcriber.energy)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                Text(String(format: "%02d:%02d", model.elapsedSeconds / 60, model.elapsedSeconds % 60))
                    .font(.system(size: 14)).monospacedDigit()
                if model.mode == "meta" {
                    Text((model.activeSession?.transcriptionUsage?.formattedCost ?? "$0.00000") + " USD")
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityIdentifier("live-transcription-cost")
                }
            }
            HStack {
                Text(model.speechProvider.name + (model.mode == "meta" ? " · est. transcription" : ""))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4)
                Text(model.assistantConfiguration.model.split(separator: "/").last.map(String.init) ?? "Choose model")
                    .font(.system(size: 11)).foregroundStyle(MintTheme.mint).lineLimit(1)
            }
        }.padding(.horizontal, 12).padding(.vertical, 10).glowPanel()
    }
    private var peekText: String {
        if !model.transcriber.partialText.isEmpty { return model.transcriber.partialText }
        return model.activeSession?.segments.last?.text ?? (model.mode == "voz" ? "Recording locally. Tap Assist to transcribe." : "Listening for speech…")
    }
    private func transcriptPeek(maxHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expandTranscript.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Live transcript").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: expandTranscript ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    if !expandTranscript {
                        Text(peekText).font(.system(size: 16)).foregroundStyle(.primary)
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("transcript-preview")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("expand-transcript")
                .accessibilityLabel(expandTranscript ? "Collapse live transcript" : "Expand live transcript")
            if expandTranscript {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(model.activeSession?.segments ?? []) { Text($0.text).frame(maxWidth: .infinity, alignment: .leading) }
                            if !model.transcriber.partialText.isEmpty { Text(model.transcriber.partialText).foregroundStyle(.secondary) }
                            Color.clear.frame(height: 1).id("transcript-bottom")
                        }.font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: maxHeight).accessibilityIdentifier("live-transcript")
                        .onAppear { proxy.scrollTo("transcript-bottom", anchor: .bottom) }
                        .onChange(of: model.activeSession?.segments.count) { _, _ in proxy.scrollTo("transcript-bottom", anchor: .bottom) }
                        .onChange(of: model.transcriber.partialText) { _, _ in proxy.scrollTo("transcript-bottom", anchor: .bottom) }
                }
            }
        }.padding(12).glowPanel()
    }
    private var answerFeed: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 1).id("answer-top")
                    if let error = model.assistError {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Assist could not finish", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                                .font(.system(size: 14, weight: .semibold))
                            Text(error).font(.system(size: 14)).accessibilityIdentifier("assist-error")
                            Text("No automatic retry. Any partial answer below is incomplete.")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("Retry same text") { Task { await model.assist(reuseText: true) } }
                                .disabled(model.isAssisting || model.lastAssistRequest == nil)
                                .accessibilityIdentifier("retry-failed-assist")
                        }.padding(14).glowPanel()
                    }
                    if model.isAssisting || !model.streamingAnswer.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(model.assistError == nil ? model.assistStage : "Incomplete answer", systemImage: "sparkles")
                                    .font(.system(size: 13, weight: .medium)).foregroundStyle(MintTheme.mint)
                                Spacer()
                                if model.isAssisting { ProgressView().controlSize(.small) }
                            }
                            if !model.streamingAnswer.isEmpty {
                                Text(model.streamingAnswer).font(.system(size: 16)).textSelection(.enabled)
                                    .accessibilityIdentifier("streaming-answer")
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glowPanel(highlight: true)
                    }
                    ForEach(Array((model.activeSession?.assistantTurns ?? []).reversed())) { turn in
                        InlineAssistantCard(turn: turn, latest: turn.id == model.latestAnswer?.id)
                    }
                    if model.activeSession?.assistantTurns.isEmpty != false && !model.isAssisting && model.assistError == nil {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Your assistant", systemImage: "sparkles").font(.system(size: 16, weight: .semibold)).foregroundStyle(MintTheme.mint)
                            Text("Tap Assist when you want help with a question. Answers appear here while the conversation keeps going.")
                                .font(.system(size: 16)).foregroundStyle(.secondary)
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glowPanel()
                    }
                }.padding(.bottom, 4)
            }.accessibilityIdentifier("assistant-feed")
                .onChange(of: model.latestAnswer?.id) { _, _ in withAnimation { proxy.scrollTo("answer-top", anchor: .top) } }
                .onChange(of: model.isAssisting) { _, value in if value { proxy.scrollTo("answer-top", anchor: .top) } }
                .onChange(of: model.assistError) { _, value in if value != nil { proxy.scrollTo("answer-top", anchor: .top) } }
        }
    }
    private var controls: some View {
        HStack(spacing: 12) {
            Button { Task { await model.togglePause() } } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill").frame(width: 44, height: 44)
            }.buttonStyle(MintRoundStyle()).accessibilityLabel(model.isPaused ? "Resume" : "Pause").accessibilityIdentifier("pause-session")
                .disabled(model.isAssisting || model.isTransitioning)
            Button { Task { await model.assist() } } label: {
                HStack {
                    if model.isAssisting { ProgressView() }
                    Label(model.isAssisting ? "Replying…" : "Assist", systemImage: "sparkles")
                }.frame(maxWidth: .infinity)
            }.buttonStyle(MintActionStyle()).disabled(model.isAssisting || model.isTransitioning).accessibilityIdentifier("assist-button")
            Button { Task { await model.endSession() } } label: {
                if model.isTransitioning { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "stop.fill").frame(width: 44, height: 44) }
            }.buttonStyle(MintRoundStyle()).disabled(model.isAssisting || model.isTransitioning).accessibilityLabel("Stop conversation").accessibilityIdentifier("end-session")
        }.padding(.top, 3)
    }
}

private struct InlineAssistantCard: View {
    @EnvironmentObject private var model: AppModel
    let turn: AssistantTurn
    let latest: Bool
    @State private var showDetails = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Assistant", systemImage: "sparkles").font(.system(size: 13)).foregroundStyle(MintTheme.mint)
                Spacer()
                if latest { Text("Latest").font(.system(size: 11, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 4).background(MintTheme.teal, in: Capsule()) }
            }
            if turn.detectedQuestion != "Latest conversation" {
                Text(turn.detectedQuestion).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(turn.answer).font(.system(size: 16)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(latest ? "assistant-answer" : "previous-assistant-answer")
            if !turn.details.isEmpty {
                Button(showDetails ? "Hide detail" : "More detail") { showDetails.toggle() }.font(.system(size: 13))
                if showDetails { Text(turn.details).font(.system(size: 16)).foregroundStyle(.secondary) }
            }
            if let metrics = turn.performance {
                HStack {
                    Text(String(format: "%.2f s", metrics.totalMs / 1000)).monospacedDigit()
                    if let cost = metrics.execution?.usage?.costCredits { Text(String(format: "· $%.6f", cost)).monospacedDigit() }
                    Spacer()
                    Button { UIPasteboard.general.string = turn.answer } label: { Image(systemName: "square.on.square").frame(width: 44, height: 44) }
                        .accessibilityLabel("Copy answer")
                }.font(.system(size: 12)).foregroundStyle(.secondary)
                DisclosureGroup("Timing & usage") { PerformanceView(metrics: metrics).padding(.top, 8) }
                    .font(.system(size: 13)).accessibilityIdentifier(latest ? "timing-disclosure" : "previous-timing")
            }
            if latest {
                Button("Retry same text with selected model") { Task { await model.assist(reuseText: true) } }
                    .font(.system(size: 12)).disabled(model.isAssisting || model.lastAssistRequest == nil).accessibilityIdentifier("retry-same-text")
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).glowPanel(highlight: latest)
    }
}
