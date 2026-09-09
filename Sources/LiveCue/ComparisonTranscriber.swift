import AVFoundation
import CoreML
import FluidAudio
import Foundation
import LiveCueCore
import Voz

@MainActor
final class ComparisonTranscriber: ObservableObject {
    @Published var status = "Prepare a model"
    @Published var partialText = ""
    @Published var energy: Float = 0
    @Published var timing = ""
    @Published var lastLiveChunkMs: Double?
    @Published var preparationFraction: Double = 0
    @Published var preparationStarted: Date?
    @Published var preparationFinished: Date?
    @Published var preparationBytes = ""
    private var preparationID: UUID?
    private var voz: Voz?
    private var live: StreamingEouAsrManager?
    private var variant = "voz"
    private var engine: AVAudioEngine?
    private var consumer: Task<Void, Never>?
    private var continuation: AsyncStream<[Float]>.Continuation?
    private var samples: [Float] = []
    private var cursor = 0
    private var generation = UUID()
    var onFinalSegments: (([LiveCueCore.TranscriptSegment]) -> Void)?
    var onError: ((String) -> Void)?
    static let catalog: [TranscriptionModel] = [
        .init(variant: "voz", displayName: "Voz on Assist", approximateMegabytes: 467, quality: "Transcribes when you tap Assist", recommended: true),
        .init(variant: "parakeet", displayName: "Live Parakeet", approximateMegabytes: 230, quality: "English live captions · 320 ms mode", recommended: true)
    ]
    func prepare(model: TranscriptionModel) async throws {
        let preparation = UUID(); preparationID = preparation
        preparationStarted = .now; preparationFinished = nil
        preparationFraction = 0; preparationBytes = ""
        defer { preparationID = nil; preparationFinished = .now }
        status = "Downloading and preparing \(model.displayName)…"
        variant = model.variant
        do {
            if variant == "voz" {
                await live?.cleanup(); live = nil
                if voz == nil {
                    voz = try await Voz(progress: { [weak self] progress in
                        Task { @MainActor in
                            guard let self, self.preparationID == preparation else { return }
                            self.preparationFraction = progress.fraction
                            self.preparationBytes = "\(ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file))"
                            self.status = progress.fraction >= 1 ? "Download complete · preparing Neural Engine…" : "Downloading Voz…"
                        }
                    })
                }
            } else {
                voz = nil
                if live == nil {
                    let config = MLModelConfiguration(); config.computeUnits = .cpuAndNeuralEngine
                    let manager = StreamingEouAsrManager(configuration: config, chunkSize: .ms320, eouDebounceMs: 640)
                    try await manager.loadModels(to: nil, configuration: nil, progressHandler: { [weak self] progress in
                        Task { @MainActor in
                            guard let self, self.preparationID == preparation else { return }
                            self.preparationFraction = max(0, min(1, progress.fractionCompleted))
                            switch progress.phase {
                            case .listing: self.status = "Checking model files…"
                            case .downloading(let completed, let total):
                                self.status = "Downloading Parakeet…"
                                self.preparationBytes = "\(completed) / \(total) files"
                            case .compiling: self.status = "Download complete · preparing model…"
                            }
                        }
                    }); live = manager
                }
            }
            preparationFraction = 1; status = "Ready"
        } catch { status = "Preparation failed"; throw error }
    }
    func start() async throws {
        guard engine == nil else { return }
        generation = UUID(); let id = generation
        partialText = ""; timing = ""; samples = []; cursor = 0
        if variant == "voz", voz == nil { throw failure("Prepare Voz first.") }
        if variant == "parakeet", live == nil { throw failure("Prepare Parakeet first.") }
        if let live {
            await live.reset()
            await live.setPartialCallback { [weak self] text in
                Task { @MainActor in guard let self, self.generation == id else { return }; self.partialText = text }
            }
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let audioEngine = AVAudioEngine(), format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let input = audioEngine.inputNode, source = audioEngine.inputNode.outputFormat(forBus: 0)
        guard source.sampleRate > 0, source.channelCount > 0, let converter = AVAudioConverter(from: source, to: format) else { throw failure("No usable microphone.") }
        let stream = AsyncStream<[Float]>(bufferingPolicy: .bufferingOldest(128)) { self.continuation = $0 }
        let sink = continuation!
        input.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16000 / source.sampleRate) + 32)
            guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: pcm, error: &error) { _, state in
                if supplied { state.pointee = .noDataNow; return nil }
                supplied = true; state.pointee = .haveData; return buffer
            }
            guard error == nil, let channel = pcm.floatChannelData?[0], pcm.frameLength > 0 else { return }
            let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(pcm.frameLength)))
            if case .dropped = sink.yield(chunk) {
                Task { @MainActor in self?.onError?("Transcription could not keep up. Stop and restart the session.") }
            }
        }
        consumer = Task { [weak self] in
            for await chunk in stream {
                guard let self, !Task.isCancelled, self.generation == id else { break }
                self.energy = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(max(1, chunk.count)))
                if self.variant == "voz" {
                    guard self.samples.count + chunk.count <= 16000 * 60 * 30 else {
                        self.onError?("Pending recording reached 30 minutes. Tap Assist to transcribe it."); self.stop(); break
                    }
                    self.samples.append(contentsOf: chunk)
                } else if let live = self.live {
                    guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunk.count)) else { continue }
                    pcm.frameLength = pcm.frameCapacity
                    chunk.withUnsafeBufferPointer { pcm.floatChannelData![0].update(from: $0.baseAddress!, count: chunk.count) }
                    let started = ProcessInfo.processInfo.systemUptime
                    do {
                        _ = try await live.process(audioBuffer: pcm)
                        self.lastLiveChunkMs = (ProcessInfo.processInfo.systemUptime - started) * 1000
                        self.timing = String(format: "Last buffer processing: %.0f ms", self.lastLiveChunkMs ?? 0)
                    } catch { self.onError?(error.localizedDescription); self.stop(); break }
                }
            }
        }
        do { try audioEngine.start(); engine = audioEngine; status = "Recording" }
        catch { input.removeTap(onBus: 0); sink.finish(); consumer?.cancel(); throw error }
    }
    func transcribePending() async throws {
        guard variant == "voz", let voz else { return }
        let snapshot = samples, previousCursor = cursor, id = generation
        guard snapshot.count > previousCursor else { return }
        status = "Transcribing…"
        let started = Date()
        let result = try await voz.transcribe(samples: snapshot)
        guard generation == id else { return }
        let text = result.words.filter { $0.end > Double(previousCursor) / 16000 }.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { onFinalSegments?([.init(text: text, startSeconds: 0, endSeconds: result.duration)]) }
        let overlap = min(snapshot.count, 32000)
        samples.removeFirst(snapshot.count - overlap); cursor = overlap
        timing = String(format: "%.1f s audio → %.2f s transcription", result.duration, Date().timeIntervalSince(started))
        status = engine == nil ? "Paused" : "Recording"
    }
    func pause() async throws {
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        continuation?.finish(); continuation = nil
        await consumer?.value; consumer = nil
        if let live {
            let text = try await live.finish()
            generation = UUID()
            if !text.isEmpty { onFinalSegments?([.init(text: text, startSeconds: 0, endSeconds: 0)]) }
            partialText = ""
        } else { try await transcribePending() }
        status = "Paused"
    }
    func stop() {
        generation = UUID()
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        continuation?.finish(); continuation = nil; consumer?.cancel(); consumer = nil
        status = "Ready"; energy = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func remove(model: TranscriptionModel) throws { stop(); voz = nil; live = nil }
    private func failure(_ message: String) -> NSError { NSError(domain: "LiveCue", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
