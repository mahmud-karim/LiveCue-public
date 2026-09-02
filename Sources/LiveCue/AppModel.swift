import AVFoundation
import Foundation
import LiveCueCore

@MainActor
final class AppModel: ObservableObject {
    enum Route: Hashable { case models, history, settings, modelLab }

    @Published var sessions: [Session] = []
    @Published var activeSession: Session?
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var isAssisting = false
    @Published var instruction = ""
    @Published var latestAnswer: AssistantTurn?
    @Published var errorMessage: String?
    @Published var relayOnline = false
    @Published var endpoint = UserDefaults.standard.string(forKey: "relayEndpoint") ?? ""
    @Published var selectedModelVariant = UserDefaults.standard.string(forKey: "selectedModel")
    @Published var elapsedSeconds = 0
    @Published var benchmarks: [BenchmarkResult] = []

    let transcriber = WhisperTranscriber()
    private let relay = RelayClient()
    private let repository: SessionRepository
    private var timer: Timer?
    private var isUITesting: Bool { ProcessInfo.processInfo.arguments.contains("-ui-testing") }
    var token: String? { KeychainStore.get(account: "relayToken") }
    var isPaired: Bool { !endpoint.isEmpty && token != nil }
    var selectedModel: TranscriptionModel? { WhisperTranscriber.catalog.first { $0.variant == selectedModelVariant } }

    init() {
        repository = try! SessionRepository(inMemory: ProcessInfo.processInfo.arguments.contains("-ui-testing"))
        sessions = repository.all()
        transcriber.onFinalSegments = { [weak self] segments in self?.append(segments) }
        if isUITesting {
            selectedModelVariant = WhisperTranscriber.catalog[1].variant
            endpoint = "https://livecue.test"
        }
        Task { await checkRelay() }
    }

    func pair(endpoint rawEndpoint: String, token rawToken: String) async {
        var normalized = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasSuffix("/") { normalized += "/" }
        do {
            if !isUITesting { try await relay.verify(endpoint: normalized, token: rawToken) }
            try KeychainStore.set(rawToken, account: "relayToken")
            endpoint = normalized
            UserDefaults.standard.set(normalized, forKey: "relayEndpoint")
            relayOnline = true
        } catch { errorMessage = error.localizedDescription }
    }

    func checkRelay() async {
        guard isPaired else { relayOnline = false; return }
        if isUITesting { relayOnline = true; return }
        relayOnline = (try? await relay.health(endpoint: endpoint, token: token)) == true
    }

    func selectAndPrepare(_ model: TranscriptionModel) async {
        do {
            if !isUITesting { try await transcriber.prepare(model: model) }
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
        guard selectedModel != nil else { errorMessage = "Choose and download a transcription model first."; return }
        let granted = isUITesting || await AVAudioApplication.requestRecordPermission()
        guard granted else { errorMessage = "Microphone permission is required for live transcription."; return }
        activeSession = Session()
        latestAnswer = nil
        elapsedSeconds = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor in self?.elapsedSeconds += 1 } }
        do {
            if isUITesting {
                append([TranscriptSegment(text: "What is the main advantage of local transcription?", startSeconds: 0, endSeconds: 3)])
            } else { try await transcriber.start() }
        } catch { isRecording = false; timer?.invalidate(); errorMessage = error.localizedDescription }
    }

    func togglePause() async {
        isPaused.toggle()
        if isUITesting { return }
        if isPaused { transcriber.stop() }
        else { do { try await transcriber.start() } catch { errorMessage = error.localizedDescription } }
    }

    func assist() async {
        guard var current = activeSession else { return }
        guard let token = token ?? (isUITesting ? "test" : nil) else { errorMessage = RelayError.notPaired.localizedDescription; return }
        isAssisting = true
        defer { isAssisting = false }
        let request = ContextBuilder.makeRequest(session: current, partial: transcriber.partialText, instruction: instruction)
        do {
            let response: AssistResponse
            if isUITesting {
                response = AssistResponse(detectedQuestion: "What is the main advantage of local transcription?", answer: "Your audio stays on the iPhone, which improves privacy and keeps transcription working without a cloud speech service.", details: "Only the text context is sent through your private Tailscale connection to the Codex relay on your PC.", memory: SessionMemory(summary: "Discussing local transcription privacy.", throughSegmentId: current.segments.last?.id))
            } else { response = try await relay.assist(request, endpoint: endpoint, token: token) }
            let turn = AssistantTurn(request: request.instruction, detectedQuestion: response.detectedQuestion, answer: response.answer, details: response.details)
            current.assistantTurns.append(turn)
            current.memory = response.memory
            activeSession = current
            latestAnswer = turn
            instruction = ""
            try repository.save(current)
        } catch { errorMessage = error.localizedDescription }
    }

    func endSession() async {
        guard var current = activeSession else { return }
        transcriber.stop(); timer?.invalidate(); isRecording = false; isPaused = false
        current.endedAt = .now
        if let token = token, !isUITesting {
            if let notes = try? await relay.summarize(session: current, endpoint: endpoint, token: token) {
                current.title = notes.title
                current.notes = SessionNotes(summary: notes.summary, keyPoints: notes.keyPoints, actionItems: notes.actionItems)
            }
        } else {
            current.title = current.segments.first?.text.prefix(48).description ?? "Conversation"
        }
        try? repository.save(current)
        sessions = repository.all()
        activeSession = nil
    }

    func deleteSession(_ id: UUID) { try? repository.delete(id: id); sessions = repository.all() }

    private func append(_ segments: [TranscriptSegment]) {
        guard var current = activeSession else { return }
        current.segments.append(contentsOf: segments)
        activeSession = current
        try? repository.save(current)
    }
}

