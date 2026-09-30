import AVFoundation
import Foundation
import Combine
import LiveCueCore

@MainActor
final class AppModel: ObservableObject {
    enum Route: Hashable { case models, history, settings, modelLab }

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isAssisting = false
    @Published var instruction = UserDefaults.standard.string(forKey: "assistantInstruction") ?? "" {
        didSet { UserDefaults.standard.set(instruction, forKey: "assistantInstruction") }
    }
    @Published var latestAnswer: AssistantTurn?
    @Published var errorMessage: String?
    @Published var relayOnline = false
    @Published private(set) var connectionMessage = ""
    @Published private(set) var pairingRejected = false
    @Published private(set) var isCheckingRelay = false
    @Published var endpoint = UserDefaults.standard.string(forKey: "relayEndpoint") ?? ""
    @Published var selectedModelVariant = UserDefaults.standard.string(forKey: "selectedModel")
    @Published var elapsedSeconds = 0
    @Published var benchmarks: [BenchmarkResult] = []

    @Published var mode = SpeechProvider(rawValue: UserDefaults.standard.string(forKey: "speechProvider") ?? "")?.rawValue ?? "meta" {
        didSet { if oldValue != mode { selectedModelVariant = nil }; UserDefaults.standard.set(mode, forKey: "speechProvider") }
    }
    var speechProvider: SpeechProvider { SpeechProvider(rawValue: mode) ?? .meta }
    @Published var isPreparing = false
    @Published var isTransitioning = false
    @Published var assistStage = ""
    @Published var assistantConfiguration = (UserDefaults.standard.data(forKey: "assistantConfiguration").flatMap { try? JSONDecoder().decode(AssistantConfiguration.self, from: $0) }) ?? AssistantConfiguration() {
        didSet { if let data = try? JSONEncoder().encode(assistantConfiguration) {
            UserDefaults.standard.set(data, forKey: "assistantConfiguration")
            UserDefaults.standard.set(data, forKey: "assistantConfiguration." + assistantConfiguration.provider.rawValue)
        } }
    }
    @Published private(set) var hasOpenRouterKey = false
    @Published private(set) var openRouterKeyMessage = ""
    @Published private(set) var isVerifyingOpenRouterKey = false
    private let openRouter = OpenRouterClient()
    private var openRouterKeyAccount: String { isUITesting ? "openrouter-api-key-ui-test" : "openrouter-api-key" }
    var needsPC: Bool { speechProvider.usesPC || assistantConfiguration.provider == .codex }
    var systemReady: Bool {
        let speechReady = speechProvider.isPCLocal ? pcModelCanStart : speechProvider.usesPC ? relayOnline : selectedModel != nil
        let answerReady = assistantConfiguration.provider == .codex ? relayOnline : hasOpenRouterKey && !assistantConfiguration.model.isEmpty
        return speechReady && answerReady
    }
    func selectAssistantProvider(_ provider: AssistantProvider) {
        guard !isAssisting, provider != assistantConfiguration.provider else { return }
        if let data = try? JSONEncoder().encode(assistantConfiguration) { UserDefaults.standard.set(data, forKey: "assistantConfiguration." + assistantConfiguration.provider.rawValue) }
        assistantConfiguration = UserDefaults.standard.data(forKey: "assistantConfiguration." + provider.rawValue)
            .flatMap { try? JSONDecoder().decode(AssistantConfiguration.self, from: $0) }
            ?? (provider == .codex ? AssistantConfiguration() : AssistantConfiguration(model: "", reasoningEffort: "default", provider: .openrouter))
        assistantModels = []; modelCatalogMessage = ""
    }
    @discardableResult func saveOpenRouterKey(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else { openRouterKeyMessage = "Enter a valid API key."; return false }
        do { try KeychainStore.set(key, account: openRouterKeyAccount); hasOpenRouterKey = true; openRouterKeyMessage = "Key saved securely on this iPhone."; return true }
        catch { openRouterKeyMessage = "Could not save the key in Keychain (status \((error as NSError).code)). No insecure fallback was used."; return false }
    }
    func removeOpenRouterKey() {
        do { try KeychainStore.delete(account: openRouterKeyAccount); hasOpenRouterKey = false; openRouterKeyMessage = "Key removed." }
        catch { openRouterKeyMessage = "Keychain could not remove this key (status \((error as NSError).code)). Try again." }
    }
    func verifyOpenRouterKey() async {
        guard !isVerifyingOpenRouterKey else { return }
        guard let key = KeychainStore.get(account: openRouterKeyAccount) else { openRouterKeyMessage = OpenRouterError.missingKey.localizedDescription; return }
        isVerifyingOpenRouterKey = true; defer { isVerifyingOpenRouterKey = false }
        do { if !isUITesting { try await openRouter.verifyKey(key) }; openRouterKeyMessage = "Key verified. No inference request was made." }
        catch { openRouterKeyMessage = error.localizedDescription }
    }
    @Published var assistantModels: [AssistantModelOption] = []
    @Published var modelCatalogMessage = ""
    @Published var isLoadingModels = false
    private var catalogLoadingProvider: AssistantProvider?
    private var catalogRequestId = UUID()
    @Published private(set) var pcModelStatus: PCModelStatus?
    @Published private(set) var pcModelMessage = "Checking PC model…"
    @Published private(set) var isControllingPCModel = false
    private var isRefreshingPCModel = false
    var pcModelReady: Bool { pcModelStatus?.isReady(for: mode) == true }
    var pcModelCanStart: Bool { relayOnline && pcModelReady && pcModelStatus?.busy != true && !isControllingPCModel }
    var pcModelHomeLabel: String {
        guard isPaired else { return "Pair PC first" }
        guard relayOnline else { return "PC offline" }
        return pcModelStatus?.homeLabel(for: mode) ?? "Checking…"
    }
    func refreshPCModel() async {
        guard speechProvider.isPCLocal, !isRefreshingPCModel, !isControllingPCModel else { return }
        isRefreshingPCModel = true
        defer { isRefreshingPCModel = false }
        if isUITesting {
            if pcModelStatus == nil { pcModelStatus = PCModelStatus(state: "stopped", message: "PC model is stopped.") }
            pcModelMessage = pcModelStatus?.message ?? ""; return
        }
        guard let token, isPaired else { pcModelStatus = nil; pcModelMessage = "Pair your PC first."; return }
        do {
            pcModelStatus = try await relay.pcModelStatus(endpoint: endpoint, token: token)
            pcModelMessage = pcModelStatus?.message ?? ""
        } catch {
            pcModelStatus = nil
            pcModelMessage = "Could not check the PC model. Keep the updated LiveCue Desktop running. " + ConnectionMessage.describe(error, saved: isPaired)
        }
    }
    func controlPCModel(start: Bool) async {
        guard speechProvider.isPCLocal, !isControllingPCModel, activeSession == nil, pcModelStatus?.isChanging != true else { return }
        isControllingPCModel = true
        defer { isControllingPCModel = false }
        if isUITesting {
            pcModelStatus = PCModelStatus(state: start ? "starting" : "stopping", model: mode, message: start ? "Starting Docker and loading the PC model…" : "Unloading the PC model…")
            pcModelMessage = pcModelStatus!.message
            try? await Task.sleep(for: .seconds(start && ProcessInfo.processInfo.arguments.contains("-pc-model-slow-start") ? 6 : 1))
            if start && ProcessInfo.processInfo.arguments.contains("-pc-model-start-error") {
                pcModelStatus = PCModelStatus(state: "error", model: mode, message: "Could not load the PC model. Check Docker Desktop and retry.")
            } else {
                pcModelStatus = PCModelStatus(state: start ? "ready" : "stopped", model: start ? mode : nil, message: start ? "PC model is ready." : "PC model stopped. GPU memory released.")
            }
            pcModelMessage = pcModelStatus!.message; return
        }
        guard let token, isPaired else { pcModelMessage = "Pair your PC first."; return }
        do {
            pcModelStatus = try await relay.controlPCModel(start: start, model: mode, endpoint: endpoint, token: token)
            pcModelMessage = pcModelStatus?.message ?? ""
        } catch { pcModelMessage = ConnectionMessage.describe(error, saved: isPaired) }
    }
    @Published private(set) var lastAssistRequest: AssistRequest?
    var comparisonTurns: [AssistantTurn] {
        ((activeSession?.assistantTurns ?? []) + sessions.filter { $0.id != activeSession?.id }.flatMap(\.assistantTurns))
            .filter { $0.performance != nil }.sorted { $0.createdAt > $1.createdAt }
    }
    func refreshAssistantModels() async {
        let provider = assistantConfiguration.provider
        guard !isLoadingModels || catalogLoadingProvider != provider else { return }
        let requestId = UUID(); catalogRequestId = requestId; catalogLoadingProvider = provider
        isLoadingModels = true
        defer { if catalogRequestId == requestId { isLoadingModels = false; catalogLoadingProvider = nil } }
        if provider == .openrouter {
            do {
                let options = isUITesting ? [AssistantModelOption(id: "test/direct", name: "Direct test model", reasoningEfforts: ["default"])] : try await openRouter.models()
                guard catalogRequestId == requestId, assistantConfiguration.provider == provider else { return }
                assistantModels = options; modelCatalogMessage = "Direct from OpenRouter. Choose a model; API charges are separate from your Codex subscription."
            } catch { if catalogRequestId == requestId, assistantConfiguration.provider == provider { modelCatalogMessage = error.localizedDescription } }
            return
        }
        if isUITesting {
            if ProcessInfo.processInfo.arguments.contains("-pc-catalog-slow") { try? await Task.sleep(for: .seconds(8)) }
            guard catalogRequestId == requestId, assistantConfiguration.provider == provider else { return }
            assistantModels = [
                .init(id: "gpt-6-astra", name: "GPT-6 Astra", reasoningEfforts: ["low", "medium", "high"]),
                .init(id: "gpt-6-luna", name: "GPT-6 Luna", reasoningEfforts: ["low", "medium", "high"]),
                .init(id: "gpt-5.6-sol", name: "GPT-5.6 Sol", reasoningEfforts: ["none", "low", "medium", "high"]),
                .init(id: "gpt-5.6-luna", name: "GPT-5.6 Luna", reasoningEfforts: ["none", "low", "medium", "high"]),
                .init(id: "gpt-5.3-codex-spark", name: "Codex Spark", reasoningEfforts: ["low", "medium", "high"])
            ]; modelCatalogMessage = "Simulator test catalog; timings use fixtures."; return
        }
        guard let token, isPaired else { modelCatalogMessage = "Pair your PC first."; return }
        do {
            let options = try await relay.models(endpoint: endpoint, token: token)
            guard catalogRequestId == requestId, assistantConfiguration.provider == provider else { return }
            assistantModels = options
            modelCatalogMessage = "From this PC's Codex catalog. Access still depends on your subscription."
        } catch { if catalogRequestId == requestId, assistantConfiguration.provider == provider { modelCatalogMessage = "Could not load models. Restart the updated PC app and check the connection. " + error.localizedDescription } }
    }
    private var transcriberObservation: AnyCancellable?
    let transcriber = ComparisonTranscriber()
    private let relay = RelayClient()
    private let repository: SessionRepository
    private var timer: Timer?
    private var fixtureUsage = TranscriptionUsage()
    private var fixtureStream = UUID()
    private var fixtureStreamSeconds = 0
    private let pairingStore: PairingStore
    private var savedPairing: PairingPayload?
    private var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }
    var token: String? { savedPairing?.token }
    var isPaired: Bool { (isUITesting && !ProcessInfo.processInfo.arguments.contains("-pairing-persistence-test")) || (!endpoint.isEmpty && token != nil) }
    var selectedModel: TranscriptionModel? { ComparisonTranscriber.catalog.first { $0.variant == selectedModelVariant && $0.variant == mode } }

    init() {
        let store = PairingStore(testing: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
        pairingStore = store
        savedPairing = store.load(legacyEndpoint: UserDefaults.standard.string(forKey: "relayEndpoint") ?? "")
        repository = try! SessionRepository(inMemory: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
        sessions = repository.all()
        transcriber.onFinalSegments = { [weak self] segments in self?.append(segments) }
        transcriber.onError = { [weak self] message in self?.errorMessage = message; if self?.speechProvider.usesPC == true { self?.isPaused = true } }
        transcriberObservation = transcriber.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        selectedModelVariant = nil
        if isUITesting {
            mode = "meta"
            if !ProcessInfo.processInfo.arguments.contains("-openrouter-persistence-test") { assistantConfiguration = AssistantConfiguration() }
            selectedModelVariant = "voz"
            if ProcessInfo.processInfo.arguments.contains("-on-device-ready") { mode = "parakeet"; selectedModelVariant = "parakeet" }
            if ProcessInfo.processInfo.arguments.contains("-save-pairing-fixture") {
                let fixture = try! PairingPayload.parse("{\"endpoint\":\"https://saved-pc.example.test:10000/\",\"token\":\"persistent-synthetic-test-token\"}")
                try! pairingStore.save(fixture)
                savedPairing = fixture
            }
            if ProcessInfo.processInfo.arguments.contains("-drop-test-keychain") {
                pairingStore.removeTestKeychainCopy()
                savedPairing = pairingStore.load()
            }
            endpoint = "https://livecue.test"
            relayOnline = true
        }
        if isUITesting && ProcessInfo.processInfo.arguments.contains("-openrouter-ui-reset") { KeychainStore.remove(account: openRouterKeyAccount) }
        hasOpenRouterKey = KeychainStore.get(account: openRouterKeyAccount) != nil
        if let savedPairing, !isUITesting || ProcessInfo.processInfo.arguments.contains("-pairing-persistence-test") { endpoint = savedPairing.endpoint }
        Task { await checkRelay() }
    }

    func pair(endpoint rawEndpoint: String, token rawToken: String) async {
        var normalized = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasSuffix("/") { normalized += "/" }
        do {
            let data = try JSONSerialization.data(withJSONObject: ["endpoint": normalized, "token": rawToken])
            let pairing = try PairingPayload.parse(String(decoding: data, as: UTF8.self))
            if !isUITesting { try await relay.verify(endpoint: normalized, token: rawToken) }
            try pairingStore.save(pairing)
            savedPairing = pairing
            endpoint = normalized
            UserDefaults.standard.set(normalized, forKey: "relayEndpoint")
            relayOnline = true
            pairingRejected = false; connectionMessage = "Connected. Your pairing is saved on this iPhone."
        } catch { errorMessage = ConnectionMessage.describe(error, saved: isPaired) }
    }

    func checkRelay() async {
        guard !isCheckingRelay else { return }
        if savedPairing == nil, let restored = pairingStore.load(legacyEndpoint: endpoint) { savedPairing = restored; endpoint = restored.endpoint }
        guard isPaired else { relayOnline = false; return }
        if isUITesting { relayOnline = !ProcessInfo.processInfo.arguments.contains("-pc-offline"); connectionMessage = relayOnline ? "Connected. Your pairing is saved on this iPhone." : "PC offline."; return }
        isCheckingRelay = true
        defer { isCheckingRelay = false }
        do {
            relayOnline = try await relay.health(endpoint: endpoint, token: token)
            pairingRejected = false; connectionMessage = "Connected. Your pairing is saved on this iPhone."
            if speechProvider.isPCLocal { await refreshPCModel() }
        } catch {
            relayOnline = false
            if let relayError = error as? RelayError, case .unauthorized = relayError { pairingRejected = true }
            connectionMessage = ConnectionMessage.describe(error, saved: !pairingRejected)
        }
    }

    func selectAndPrepare(_ model: TranscriptionModel) async {
        guard !isPreparing, activeSession == nil else { return }
        isPreparing = true
        defer { isPreparing = false }
        do {
            if !isUITesting { try await transcriber.prepare(model: model) }
            else {
                transcriber.preparationStarted = .now; transcriber.preparationFinished = nil
                transcriber.preparationFraction = 0.5; transcriber.status = "Downloading test fixture…"
                try await Task.sleep(for: .seconds(2))
                transcriber.preparationFraction = 1; transcriber.preparationFinished = .now; transcriber.status = "Ready"
            }
            selectedModelVariant = model.variant
            UserDefaults.standard.set(model.variant, forKey: "selectedModel")
        } catch { errorMessage = error.localizedDescription }
    }

    func remove(_ model: TranscriptionModel) {
        do {
            if !isUITesting { try transcriber.remove(model: model) }
            if selectedModelVariant == model.variant { selectedModelVariant = nil; UserDefaults.standard.removeObject(forKey: "selectedModel") }
        } catch { errorMessage = error.localizedDescription }
    }

    func startSession() async {
        guard activeSession == nil, !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        guard speechProvider.usesPC || selectedModel != nil else { errorMessage = "Choose and download a transcription model first."; return }
        if speechProvider.isPCLocal {
            await refreshPCModel()
            guard pcModelCanStart else { errorMessage = "PC speech model: \(pcModelHomeLabel). Open Transcription settings to start it or check its status."; return }
        }
        if speechProvider.usesPC, !isUITesting {
            guard isPaired else { errorMessage = RelayError.notPaired.localizedDescription; return }
            if !relayOnline { await checkRelay() }
            guard relayOnline, let token else { errorMessage = connectionMessage; return }
            transcriber.useCloud(provider: speechProvider); transcriber.cloudEndpoint = endpoint; transcriber.cloudToken = token; transcriber.cloudOffset = 0
        }
        let granted: Bool
        if isUITesting { granted = true }
        else { granted = await AVAudioApplication.requestRecordPermission() }
        guard granted else { errorMessage = "Microphone permission is required for live transcription."; return }
        activeSession = Session()
        transcriber.resetCloudUsage(provider: mode)
        activeSession?.transcriptionUsage = TranscriptionUsage(provider: mode)
        fixtureUsage = TranscriptionUsage(provider: mode); fixtureStream = UUID(); fixtureStreamSeconds = 0
        if isUITesting && speechProvider.usesPC { fixtureUsage.begin(fixtureStream) }
        latestAnswer = nil
        lastAssistRequest = nil
        elapsedSeconds = 0
        isRecording = true
        isPaused = false
        let sessionTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer = sessionTimer
        RunLoop.main.add(sessionTimer, forMode: .common)
        do {
            if isUITesting {
                append([TranscriptSegment(text: "What is the main advantage of local transcription?", startSeconds: 0, endSeconds: 3)])
            } else { try await transcriber.start() }
        } catch { transcriber.stop(); activeSession = nil; isRecording = false; timer?.invalidate(); errorMessage = error.localizedDescription }
    }

    func togglePause() async {
        guard !isAssisting, !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        isPaused.toggle()
        if isUITesting {
            if isPaused { fixtureUsage.finish(fixtureStream, completed: true) }
            else { fixtureStream = UUID(); fixtureStreamSeconds = 0; fixtureUsage.begin(fixtureStream) }
            captureUsage(); return
        }
        if isPaused { do { try await transcriber.pause() } catch { errorMessage = error.localizedDescription } }
        else { do { transcriber.cloudOffset = Double(elapsedSeconds); try await transcriber.start() } catch { isPaused = true; errorMessage = error.localizedDescription } }
        captureUsage()
    }

    func assist(reuseText: Bool = false) async {
        guard activeSession != nil, !isAssisting, !isTransitioning else { return }
        let token = token ?? (isUITesting ? "test" : nil)
        if assistantConfiguration.provider == .codex && token == nil { errorMessage = RelayError.notPaired.localizedDescription; return }
        if assistantConfiguration.provider == .openrouter && !hasOpenRouterKey { errorMessage = OpenRouterError.missingKey.localizedDescription; return }
        isAssisting = true
        let totalStarted = ProcessInfo.processInfo.systemUptime
        let configuration = assistantConfiguration
        defer { isAssisting = false; assistStage = "" }
        do {
            assistStage = mode == "voz" ? "Transcribing…" : "Thinking…"
            let sttStarted = ProcessInfo.processInfo.systemUptime
            if !isUITesting && !reuseText { try await transcriber.transcribePending() }
            let sttMs = reuseText || mode != "voz" ? 0 : (ProcessInfo.processInfo.systemUptime - sttStarted) * 1000
            let contextStarted = ProcessInfo.processInfo.systemUptime
            guard let current = activeSession else { return }
            var request = reuseText ? (lastAssistRequest ?? ContextBuilder.makeRequest(session: current, partial: transcriber.partialText, instruction: instruction)) : ContextBuilder.makeRequest(session: current, partial: transcriber.partialText, instruction: instruction)
            request.requestId = UUID()
            request.assistant = configuration
            guard !request.transcript.isEmpty || !(request.partialTranscript ?? "").isEmpty else {
                errorMessage = "No speech was recognized yet."; return
            }
            // Refresh before sending text, but never silently switch the user's model.
            assistStage = "Checking model…"
            if configuration.provider == .openrouter {
                if assistantModels.isEmpty { await refreshAssistantModels() }
            } else if isUITesting { await refreshAssistantModels() }
            else { assistantModels = try await relay.models(endpoint: endpoint, token: token!) }
            guard let option = assistantModels.first(where: { $0.id == configuration.model && $0.reasoningEfforts.contains(configuration.reasoningEffort) }) else {
                if configuration.provider == .openrouter { throw OpenRouterError.noModel }
                throw RelayError.server("\(configuration.model) / \(configuration.reasoningEffort) is not in this PC's current catalog. Open Assistant models & timing and choose an available combination. Your selection has not changed.")
            }
            assistStage = "Thinking…"
            lastAssistRequest = request
            let contextMs = (ProcessInfo.processInfo.systemUptime - contextStarted) * 1000
            let roundTripStarted = ProcessInfo.processInfo.systemUptime
            var response: AssistResponse
            if isUITesting {
                response = AssistResponse(detectedQuestion: "What is the main advantage of local transcription?", answer: "Your audio stays on the iPhone, which improves privacy and keeps transcription working without a cloud speech service.", details: "Only the text context is sent through your private Tailscale connection to the Codex relay on your PC.", memory: SessionMemory(summary: "Discussing local transcription privacy.", throughSegmentId: current.segments.last?.id))
                response.execution = RelayExecution(model: configuration.model, reasoningEffort: configuration.reasoningEffort, codexMs: 600, relayTotalMs: 620, requestReadMs: 2, relayOverheadMs: 20)
                if configuration.provider == .openrouter { response.execution?.usage = AssistantUsage(promptTokens: 120, completionTokens: 40, costCredits: 0.0001) }
            } else if configuration.provider == .openrouter {
                guard let key = KeychainStore.get(account: openRouterKeyAccount) else { throw OpenRouterError.missingKey }
                response = try await openRouter.assist(request, option: option, key: key, throughSegmentId: current.segments.last?.id)
            } else { response = try await relay.assist(request, endpoint: endpoint, token: token!) }
            if configuration.provider == .codex {
              guard let execution = response.execution,
                  execution.model == configuration.model,
                  execution.reasoningEffort == configuration.reasoningEffort else {
                throw RelayError.server("The PC did not confirm the selected model. Restart the updated LiveCue Desktop app, then retry.")
              }
            }
            let roundTripMs = isUITesting ? 680 : (ProcessInfo.processInfo.systemUptime - roundTripStarted) * 1000
            let metrics = AssistPerformance(configuration: configuration, speechModel: mode, reusedText: reuseText, transcriptionMs: sttMs, contextMs: contextMs, roundTripMs: roundTripMs, totalMs: isUITesting ? 700 : (ProcessInfo.processInfo.systemUptime - totalStarted) * 1000, lastLiveChunkMs: mode == "parakeet" ? transcriber.lastLiveChunkMs : nil, transcriptCharacters: request.transcript.count + (request.partialTranscript?.count ?? 0), execution: response.execution)
            let turn = AssistantTurn(request: request.instruction, detectedQuestion: response.detectedQuestion, answer: response.answer, details: response.details, performance: metrics)
            guard var latest = activeSession, latest.id == current.id else { return }
            latest.assistantTurns.append(turn)
            latest.memory = response.memory
            activeSession = latest
            latestAnswer = turn
            try repository.save(latest)
        } catch { errorMessage = error.localizedDescription }
    }

    func endSession() async {
        guard activeSession != nil, !isAssisting, !isTransitioning else { return }
        isTransitioning = true
        defer { isTransitioning = false }
        if !isUITesting { do { try await transcriber.pause() } catch { errorMessage = error.localizedDescription } }
        else { fixtureUsage.finish(fixtureStream, completed: true) }
        captureUsage()
        guard var current = activeSession else { return }
        transcriber.stop(); timer?.invalidate(); isRecording = false; isPaused = false
        current.endedAt = .now
        current.title = current.segments.first?.text.prefix(48).description ?? "Conversation"
        try? repository.save(current)
        sessions = repository.all()
        activeSession = nil
        // Return navigation after audio drains, without waiting on a summary.
        if let token = token, !isUITesting, assistantConfiguration.provider == .codex {
            let saved = current, configuration = assistantConfiguration, address = endpoint
            Task {
                if let notes = try? await relay.summarize(session: saved, endpoint: address, token: token, assistant: configuration),
                   repository.all().contains(where: { $0.id == saved.id }) {
                    var updated = saved
                    updated.title = notes.title
                    updated.notes = SessionNotes(summary: notes.summary, keyPoints: notes.keyPoints, actionItems: notes.actionItems)
                    try? repository.save(updated); sessions = repository.all()
                }
            }
        }
    }

    func deleteSession(_ id: UUID) { try? repository.delete(id: id); sessions = repository.all() }

    private func tick() {
        guard activeSession != nil else { return }
        elapsedSeconds += 1
        if isUITesting, speechProvider.usesPC, !isPaused, !isTransitioning {
            fixtureStreamSeconds += 1
            fixtureUsage.update(fixtureStream, sentMs: Double(fixtureStreamSeconds * 1000), processedMs: Double(fixtureStreamSeconds * 1000), hasTranscript: true)
            transcriber.energy = Float(0.025 + 0.02 * sin(Double(elapsedSeconds)))
        }
        captureUsage()
    }

    private func captureUsage() {
        guard var current = activeSession else { return }
        if speechProvider.usesPC { current.transcriptionUsage = isUITesting ? fixtureUsage : transcriber.cloudUsage }
        activeSession = current
        try? repository.save(current)
    }

    private func append(_ segments: [TranscriptSegment]) {
        guard var current = activeSession else { return }
        current.segments.append(contentsOf: segments)
        if speechProvider.usesPC { current.segments.sort { $0.startSeconds < $1.startSeconds } }
        activeSession = current
        try? repository.save(current)
    }
}
