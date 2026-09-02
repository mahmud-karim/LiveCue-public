import Foundation
import WhisperKit
import LiveCueCore

@MainActor
final class WhisperTranscriber: ObservableObject {
    @Published private(set) var status = "No model loaded"
    @Published private(set) var partialText = ""
    @Published private(set) var energy: Float = 0
    @Published private(set) var installedVariant: String?

    private var kit: WhisperKit?
    private var stream: AudioStreamTranscriber?
    private var streamTask: Task<Void, Never>?
    private var knownConfirmedCount = 0
    var onFinalSegments: (([LiveCueCore.TranscriptSegment]) -> Void)?

    static let catalog: [LiveCueCore.TranscriptionModel] = [
        .init(variant: "openai_whisper-tiny.en", displayName: "Tiny English", approximateMegabytes: 75, quality: "Fastest; useful for testing", recommended: false),
        .init(variant: "openai_whisper-base.en", displayName: "Base English", approximateMegabytes: 145, quality: "Balanced speed and accuracy", recommended: true),
        .init(variant: "openai_whisper-small.en", displayName: "Small English", approximateMegabytes: 465, quality: "More accurate; slower", recommended: false),
        .init(variant: "distil-whisper_distil-large-v3_594MB", displayName: "Distil Large v3", approximateMegabytes: 594, quality: "High accuracy", recommended: false),
        .init(variant: "openai_whisper-large-v3-v20240930_626MB", displayName: "Large v3", approximateMegabytes: 626, quality: "Best accuracy; heaviest", recommended: false)
    ]

    func prepare(model: LiveCueCore.TranscriptionModel) async throws {
        status = "Downloading \(model.displayName)…"
        let base = try modelBaseDirectory()
        let config = WhisperKitConfig(
            model: model.variant,
            downloadBase: base,
            modelRepo: "argmaxinc/whisperkit-coreml",
            verbose: false,
            prewarm: true,
            load: true,
            download: true,
            useBackgroundDownloadSession: true
        )
        let loaded = try await WhisperKit(config)
        kit = loaded
        installedVariant = model.variant
        status = "Ready"
    }

    func start() async throws {
        guard let kit, let tokenizer = kit.tokenizer else { throw NSError(domain: "LiveCue", code: 1, userInfo: [NSLocalizedDescriptionKey: "Download and load a transcription model first."]) }
        knownConfirmedCount = 0
        let created = AudioStreamTranscriber(
            audioEncoder: kit.audioEncoder,
            featureExtractor: kit.featureExtractor,
            segmentSeeker: kit.segmentSeeker,
            textDecoder: kit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: kit.audioProcessor,
            decodingOptions: DecodingOptions(task: .transcribe, language: "en"),
            requiredSegmentsForConfirmation: 2,
            silenceThreshold: 0.3,
            useVAD: true
        ) { [weak self] _, state in
            Task { @MainActor [weak self] in self?.consume(state) }
        }
        stream = created
        status = "Listening"
        streamTask = Task { [weak self] in
            do { try await created.startStreamTranscription() }
            catch { await MainActor.run { self?.status = error.localizedDescription } }
        }
    }

    func stop() {
        if let stream { Task { await stream.stopStreamTranscription() } }
        streamTask?.cancel()
        streamTask = nil
        status = installedVariant == nil ? "No model loaded" : "Ready"
    }

    func remove(model: LiveCueCore.TranscriptionModel) throws {
        stop()
        kit = nil
        let base = try modelBaseDirectory()
        let target = base.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(model.variant)")
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        if installedVariant == model.variant { installedVariant = nil; status = "No model loaded" }
    }

    private func consume(_ state: AudioStreamTranscriber.State) {
        partialText = state.currentText.isEmpty ? state.unconfirmedText.joined(separator: " ") : state.currentText
        energy = state.bufferEnergy.last ?? 0
        guard state.confirmedSegments.count > knownConfirmedCount else { return }
        let new = state.confirmedSegments.dropFirst(knownConfirmedCount).map {
            LiveCueCore.TranscriptSegment(text: $0.text, startSeconds: Double($0.start), endSeconds: Double($0.end), isFinal: true)
        }
        knownConfirmedCount = state.confirmedSegments.count
        onFinalSegments?(Array(new))
    }

    private func modelBaseDirectory() throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveCueModels", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var mutable = base; try? mutable.setResourceValues(values)
        return base
    }
}
