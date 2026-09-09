import SwiftUI
import LiveCueCore

struct PairingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var endpoint = ""
    @State private var token = ""
    @State private var pairingPayload = ""
    @State private var scanning = false

    var body: some View {
        Form {
            Section {
                Button { scanning = true } label: { Label("Scan PC QR code", systemImage: "qrcode.viewfinder") }.accessibilityIdentifier("scan-pairing-qr")
                Text("Start LiveCue Relay on Windows. Paste the pairing JSON shown by the launcher, or enter the values manually.")
                TextEditor(text: $pairingPayload).frame(minHeight: 90).font(.caption.monospaced())
                Button("Read pairing payload") { parsePayload() }
            } header: { Text("Quick pairing") }
            Section("Manual pairing") {
                TextField("https://your-pc.tailnet.ts.net", text: $endpoint).textInputAutocapitalization(.never).keyboardType(.URL)
                SecureField("Pairing token", text: $token).textInputAutocapitalization(.never)
                Button("Verify and pair") { Task { await model.pair(endpoint: endpoint, token: token) } }.disabled(endpoint.isEmpty || token.isEmpty)
                if model.relayOnline { Label("PC connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            Section("Privacy") { Text("The token is stored in the iPhone Keychain. The relay is reachable only inside your Tailscale network and never stores conversation text in its logs.") }
        }
        .navigationTitle("Pair Windows PC")
        .onAppear { endpoint = model.endpoint }
        .sheet(isPresented: $scanning) {
            NavigationStack {
                QRScanner { result in
                    scanning = false
                    switch result {
                    case .success(let value): pairingPayload = value; parsePayload()
                    case .failure(let error): model.errorMessage = error.localizedDescription
                    }
                }
                .overlay(alignment: .bottom) { Text("Point at the QR in LiveCue Desktop").padding().background(.regularMaterial, in: Capsule()).padding() }
                .navigationTitle("Scan PC QR")
                .toolbar { Button("Cancel") { scanning = false } }
            }
        }
    }

    private func parsePayload() {
        do {
            let value = try PairingPayload.parse(pairingPayload)
            endpoint = value.endpoint; token = value.token; pairingPayload = ""
        } catch { model.errorMessage = error.localizedDescription }
    }
}

struct ModelLibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var workingVariant: String?
    var body: some View {
        List {
            Section {
                Text("Prepare the model for this tab once. The download is cached on your iPhone. Initial preparation can take longer than subsequent loads.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("English models") {
                ForEach(ComparisonTranscriber.catalog.filter { $0.variant == model.mode }) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading) {
                                HStack { Text(item.displayName).font(.headline); if item.recommended { Text("RECOMMENDED").font(.caption2.bold()).foregroundStyle(.indigo) } }
                                Text("~\(item.approximateMegabytes) MB · \(item.quality)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.selectedModelVariant == item.variant { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
                        }
                        HStack {
                            Button(model.selectedModelVariant == item.variant ? "Reload" : "Download & use") {
                                workingVariant = item.variant
                                Task { await model.selectAndPrepare(item); workingVariant = nil }
                            }.buttonStyle(.borderedProminent).disabled(workingVariant != nil)
                            if model.selectedModelVariant == item.variant {
                                Button("Unload") { model.remove(item) }.buttonStyle(.bordered).disabled(model.isPreparing)
                            }
                            if workingVariant == item.variant { ProgressView() }
                        }
                        if let started = model.transcriber.preparationStarted {
                            ProgressView(value: model.transcriber.preparationFraction).accessibilityIdentifier("model-download-progress")
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let elapsed = max(0, Int((model.transcriber.preparationFinished ?? context.date).timeIntervalSince(started)))
                                HStack {
                                    Text("\(Int(model.transcriber.preparationFraction * 100))% setup")
                                    Spacer()
                                    Text(String(format: "%02d:%02d elapsed", elapsed / 60, elapsed % 60)).monospacedDigit()
                                }.font(.caption)
                            }
                            Text(model.transcriber.status).font(.caption)
                            if !model.transcriber.preparationBytes.isEmpty { Text(model.transcriber.preparationBytes).font(.caption).foregroundStyle(.secondary) }
                            Text("Downloading and model preparation are separate steps; preparation can continue after the download reaches 100%.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
            }
            Section("Pinned source") {
                Text(model.transcriber.status)
                LabeledContent("Package", value: model.mode == "voz" ? "Desert Ant 3.1.0" : "FluidAudio 0.15.6")
            }
        }.navigationTitle("Model Library")
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        List {
            if model.sessions.isEmpty { ContentUnavailableView("No conversations yet", systemImage: "waveform", description: Text("Completed sessions will appear here.")) }
            ForEach(model.sessions) { session in
                NavigationLink { SessionDetailView(session: session) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.title).font(.headline).lineLimit(2)
                        Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                        Text("\(session.segments.count) transcript segments · \(session.assistantTurns.count) assists").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.onDelete { offsets in offsets.map { model.sessions[$0].id }.forEach(model.deleteSession) }
        }.navigationTitle("History")
    }
}

struct SessionDetailView: View {
    let session: Session
    var body: some View {
        List {
            if !session.notes.summary.isEmpty { Section("Summary") { Text(session.notes.summary) } }
            if !session.notes.keyPoints.isEmpty { Section("Key points") { ForEach(session.notes.keyPoints, id: \.self) { Label($0, systemImage: "circle.fill") } } }
            if !session.notes.actionItems.isEmpty { Section("Action items") { ForEach(session.notes.actionItems, id: \.self) { Label($0, systemImage: "checkmark.circle") } } }
            Section("Transcript") { ForEach(session.segments) { Text($0.text) } }
            Section("Assistant") { ForEach(session.assistantTurns) { turn in VStack(alignment: .leading, spacing: 5) { Text(turn.detectedQuestion).font(.caption).foregroundStyle(.secondary); Text(turn.answer); if !turn.details.isEmpty { Text(turn.details).font(.callout).foregroundStyle(.secondary) } } } }
        }.navigationTitle(session.title).navigationBarTitleDisplayMode(.inline)
    }
}

struct ModelLabView: View {
    @EnvironmentObject private var model: AppModel
    @State private var reference = "The quick brown fox jumps over the lazy dog"
    @State private var hypothesis = ""
    var body: some View {
        Form {
            Section("Purpose") { Text("Record the same short phrase with different models, then compare processing time and word error rate. This first build provides the scoring worksheet; live benchmark capture uses the current session transcript.") }
            Section("Reference phrase") { TextEditor(text: $reference).frame(minHeight: 70) }
            Section("Model transcript") { TextEditor(text: $hypothesis).frame(minHeight: 70) }
            Section {
                let rate = WordErrorRate.calculate(reference: reference, hypothesis: hypothesis)
                LabeledContent("Word error rate", value: rate.formatted(.percent.precision(.fractionLength(1))))
                Button("Use latest transcript") { hypothesis = model.activeSession?.segments.map(\.text).joined(separator: " ") ?? "" }
            }
            Section("Interpretation") { Text("Lower is better. Test in the same room and speak the same phrase for a fair comparison.") }
        }.navigationTitle("Model Lab")
    }
}
