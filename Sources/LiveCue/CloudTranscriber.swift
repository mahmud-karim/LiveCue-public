import AVFoundation
import Foundation
import LiveCueCore

@MainActor
final class CloudTranscriber {
    var onUpdate: ((String, Float, String) -> Void)?
    var onFinal: (([TranscriptSegment]) -> Void)?
    var onError: ((String) -> Void)?
    private var socket: URLSessionWebSocketTask?
    private var engine: AVAudioEngine?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var sink: AsyncStream<Data>.Continuation?
    private var generation = UUID()
    private var transcript = CloudTranscript()
    private var partial = ""
    private var energy: Float = 0
    private var timing = ""
    private var ending = false
    private var finished = false
    private var sentBytes = 0
    private var firstPartial = false
    private var started = 0.0
    private var offset = 0.0
    private var audioObservers: [NSObjectProtocol] = []
    private(set) var usage = TranscriptionUsage()
    private var usageID: UUID?
    private var sampleRate = 24000
    private var stopStarted: Double?
    func resetUsage(provider: String) { stop(); usage = TranscriptionUsage(provider: provider) }

    func start(endpoint: String, token: String, offset: Double, provider: SpeechProvider) async throws {
        stop(); generation = UUID(); let id = generation
        sampleRate = provider.sampleRate; stopStarted = nil
        guard var url = URLComponents(string: endpoint), url.scheme == "https", url.host != nil else { throw failure("Pair your PC first.") }
        url.scheme = "wss"; url.path = "/v1/speech"; url.query = nil; url.fragment = nil
        guard let address = url.url else { throw failure("Invalid PC address.") }
        var request = URLRequest(url: address, timeoutInterval: 180)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue(provider.rawValue, forHTTPHeaderField: "X-LiveCue-Speech-Model")
        let ws = URLSession.shared.webSocketTask(with: request); socket = ws
        ws.maximumMessageSize = 128 * 1024
        transcript = CloudTranscript(); partial = ""; energy = 0; timing = "Connecting to \(provider.name)…"
        ending = false; finished = false; firstPartial = false; sentBytes = 0; self.offset = offset
        onUpdate?(partial, energy, timing); ws.resume()
        // Explicit timeout cancels receive as well as the handshake; no microphone starts until ready.
        let timeout = Task { try? await Task.sleep(for: .seconds(180)); if !Task.isCancelled { ws.cancel(with: .goingAway, reason: nil) } }
        defer { timeout.cancel() }
        do {
            var hello = try decode(try await ws.receive())
            while hello["type"] as? String == "loading" {
                timing = hello["message"] as? String ?? "Loading model on PC…"
                onUpdate?(partial, energy, timing)
                hello = try decode(try await ws.receive())
            }
            guard hello["type"] as? String == "ready" else { throw failure(hello["message"] as? String ?? "PC transcription is not ready.") }
            // Never fall back silently to a paid provider if a gateway drops the selection.
            guard hello["provider"] as? String == provider.rawValue,
                  hello["sampleRate"] as? Int == sampleRate else { throw failure("PC did not confirm the selected speech model. Update/restart LiveCue Desktop and its tunnel.") }
            timeout.cancel()
            timing = String(format: "Connected · %.1f s setup", (hello["handshakeMs"] as? Double ?? 0) / 1000)
            started = ProcessInfo.processInfo.systemUptime
            usageID = id; usage.begin(id)
            try capture(ws: ws, id: id)
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled, self.generation == id {
                        let event = try self.decode(try await ws.receive())
                        guard self.generation == id else { return }
                        if let message = event["message"] as? String, event["type"] as? String == "error" { throw self.failure(message) }
                        let type = event["type"] as? String ?? ""
                        if type == "streamComplete", let stopped = self.stopStarted {
                            self.usage.finalizationMs = (ProcessInfo.processInfo.systemUptime - stopped) * 1000
                            self.timing += String(format: " · Final %.2f s", self.usage.finalizationMs! / 1000)
                        }
                        let processed = event["audioProcessedMs"] as? Double ?? 0
                        self.usage.update(id, processedMs: event["audioProcessedMs"] as? Double,
                                          hasTranscript: !(event["transcript"] as? String ?? "").isEmpty)
                        if type == "transcript", !self.firstPartial, !(event["transcript"] as? String ?? "").isEmpty {
                            self.firstPartial = true
                            let firstMs = (ProcessInfo.processInfo.systemUptime - self.started) * 1000
                            if self.usage.firstTextMs == nil { self.usage.firstTextMs = firstMs }
                            self.timing = String(format: "First words · %.2f s from stream start", firstMs / 1000)
                        }
                        if var segment = self.transcript.apply(type: type, turn: event["turnId"] as? Int, text: event["transcript"] as? String, processedMs: processed) {
                            segment.startSeconds += self.offset; segment.endSeconds += self.offset
                            self.onFinal?([segment])
                        }
                        self.partial = self.transcript.partialText
                        self.onUpdate?(self.partial, self.energy, self.timing)
                    }
                } catch {
                    guard self.generation == id else { return }
                    self.finished = true
                    if self.ending, ws.closeCode == .normalClosure, let stopped = self.stopStarted {
                        self.usage.finalizationMs = (ProcessInfo.processInfo.systemUptime - stopped) * 1000
                    }
                    self.usage.finish(id, completed: self.ending && ws.closeCode == .normalClosure)
                    if !self.ending || ws.closeCode != .normalClosure {
                        self.fail(error.localizedDescription)
                    }
                }
            }
        } catch { stop(); throw failure("Transcription could not start. " + error.localizedDescription) }
    }

    private func capture(ws: URLSessionWebSocketTask, id: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let audio = AVAudioEngine(), source = audio.inputNode.outputFormat(forBus: 0)
        let rate = Double(sampleRate), frameBytes = sampleRate * 2 * 80 / 1000
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: true)!
        guard source.sampleRate > 0, let converter = AVAudioConverter(from: source, to: target) else { throw failure("No usable microphone.") }
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(64)) { self.sink = $0 }
        let output = sink!
        audio.inputNode.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * rate / source.sampleRate) + 32)
            guard let pcm = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var supplied = false; var error: NSError?
            converter.convert(to: pcm, error: &error) { _, status in
                if supplied { status.pointee = .noDataNow; return nil }
                supplied = true; status.pointee = .haveData; return buffer
            }
            guard error == nil, let channel = pcm.int16ChannelData?[0], pcm.frameLength > 0 else { return }
            let bytes = Data(bytes: channel, count: Int(pcm.frameLength) * 2)
            if case .dropped = output.yield(bytes) { Task { @MainActor in if self?.generation == id { self?.fail("Network cannot keep up. Recording paused; resume to retry.") } } }
        }
        sender = Task { [weak self] in
            guard let self else { return }
            var pending = Data()
            do {
                for await bytes in stream {
                    guard !Task.isCancelled, self.generation == id else { return }
                    pending.append(bytes)
                    while pending.count >= frameBytes {
                        let frame = Data(pending.prefix(frameBytes)); pending.removeFirst(frameBytes)
                        let power = frame.withUnsafeBytes { raw -> Float in
                            let samples = raw.bindMemory(to: Int16.self)
                            return sqrt(samples.reduce(Float(0)) { $0 + pow(Float($1) / 32768, 2) } / Float(max(1, samples.count)))
                        }
                        self.energy = power; self.onUpdate?(self.partial, power, self.timing)
                        try await ws.send(.data(frame)); self.sentBytes += frame.count
                        self.usage.update(id, sentMs: Double(self.sentBytes) / (rate * 2 / 1000))
                    }
                }
                if !pending.isEmpty {
                    try await ws.send(.data(pending)); self.sentBytes += pending.count
                    self.usage.update(id, sentMs: Double(self.sentBytes) / (rate * 2 / 1000))
                }
            } catch { if self.generation == id { self.fail("Audio connection failed. Resume to reconnect.") } }
        }
        engine = audio
        do { try audio.start() } catch { stop(); throw error }
        audioObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let value = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, value == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.fail("Microphone interrupted. Resume when your call or other audio finishes.") }
        })
        audioObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let value = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt, value == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor in self?.fail("Microphone route changed. Resume to use the current microphone.") }
        })
    }
    func pause() async throws {
        guard let ws = socket else { return }
        ending = true
        stopStarted = ProcessInfo.processInfo.systemUptime
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        sink?.finish(); sink = nil
        // Bound draining time; a stalled send must not hold the UI indefinitely.
        let deadline = Task { try? await Task.sleep(for: .seconds(15)); if !Task.isCancelled { ws.cancel(with: .goingAway, reason: nil) } }
        defer { deadline.cancel() }
        await sender?.value
        do {
            try await ws.send(.string("{\"type\":\"endStream\"}"))
            await receiver?.value
        } catch { stop(); throw failure("Could not finalize the transcript. Some final words may be missing.") }
        stop()
    }
    func stop() {
        if let usageID { usage.finish(usageID, completed: false) }; usageID = nil
        audioObservers.forEach { NotificationCenter.default.removeObserver($0) }; audioObservers.removeAll()
        generation = UUID(); ending = true
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        sink?.finish(); sink = nil; sender?.cancel(); sender = nil; receiver?.cancel(); receiver = nil
        socket?.cancel(with: .normalClosure, reason: nil); socket = nil; energy = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    private func fail(_ message: String) { stop(); onUpdate?(partial, 0, "Disconnected · resume to retry"); onError?(message) }
    private func decode(_ message: URLSessionWebSocketTask.Message) throws -> [String: Any] {
        let data: Data
        switch message { case .string(let text): data = Data(text.utf8); case .data(let bytes): data = bytes; @unknown default: throw failure("Unexpected speech response.") }
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("Unexpected speech response.") }
        return value
    }
    private func failure(_ message: String) -> NSError { NSError(domain: "LiveCueSpeech", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
