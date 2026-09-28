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

    func start(endpoint: String, token: String, offset: Double) async throws {
        stop(); generation = UUID(); let id = generation
        guard var url = URLComponents(string: endpoint), url.scheme == "https", url.host != nil else { throw failure("Pair your PC first.") }
        url.scheme = "wss"; url.path = "/v1/speech"; url.query = nil; url.fragment = nil
        guard let address = url.url else { throw failure("Invalid PC address.") }
        var request = URLRequest(url: address, timeoutInterval: 20)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let ws = URLSession.shared.webSocketTask(with: request); socket = ws
        ws.maximumMessageSize = 128 * 1024
        transcript = CloudTranscript(); partial = ""; energy = 0; timing = "Connecting to Meta through your PC…"
        ending = false; finished = false; firstPartial = false; sentBytes = 0; self.offset = offset
        onUpdate?(partial, energy, timing); ws.resume()
        // Explicit timeout cancels receive as well as the handshake; no microphone starts until ready.
        let timeout = Task { try? await Task.sleep(for: .seconds(20)); if !Task.isCancelled { ws.cancel(with: .goingAway, reason: nil) } }
        defer { timeout.cancel() }
        do {
            let hello = try decode(try await ws.receive())
            guard hello["type"] as? String == "ready" else { throw failure(hello["message"] as? String ?? "PC cloud transcription is not ready.") }
            timing = String(format: "Cloud connected · %.0f ms handshake", hello["handshakeMs"] as? Double ?? 0)
            started = ProcessInfo.processInfo.systemUptime
            try capture(ws: ws, id: id)
            receiver = Task { [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled, self.generation == id {
                        let event = try self.decode(try await ws.receive())
                        guard self.generation == id else { return }
                        if let message = event["message"] as? String, event["type"] as? String == "error" { throw self.failure(message) }
                        let type = event["type"] as? String ?? ""
                        let processed = event["audioProcessedMs"] as? Double ?? 0
                        if type == "transcript", !self.firstPartial, !(event["transcript"] as? String ?? "").isEmpty {
                            self.firstPartial = true
                            self.timing = String(format: "First words · %.2f s from stream start", ProcessInfo.processInfo.systemUptime - self.started)
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
                    if !self.ending || ws.closeCode != .normalClosure {
                        self.fail(error.localizedDescription)
                    }
                }
            }
        } catch { stop(); throw failure("Cloud transcription could not start. Check PC relay, Meta key, billing and Tailscale. " + error.localizedDescription) }
    }

    private func capture(ws: URLSessionWebSocketTask, id: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let audio = AVAudioEngine(), source = audio.inputNode.outputFormat(forBus: 0)
        let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
        guard source.sampleRate > 0, let converter = AVAudioConverter(from: source, to: target) else { throw failure("No usable microphone.") }
        let stream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(64)) { self.sink = $0 }
        let output = sink!
        audio.inputNode.installTap(onBus: 0, bufferSize: 2048, format: source) { [weak self] buffer, _ in
            let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 24000 / source.sampleRate) + 32)
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
                    while pending.count >= 3840 {
                        let frame = Data(pending.prefix(3840)); pending.removeFirst(3840)
                        let power = frame.withUnsafeBytes { raw -> Float in
                            let samples = raw.bindMemory(to: Int16.self)
                            return sqrt(samples.reduce(Float(0)) { $0 + pow(Float($1) / 32768, 2) } / Float(max(1, samples.count)))
                        }
                        self.energy = power; self.onUpdate?(self.partial, power, self.timing)
                        try await ws.send(.data(frame)); self.sentBytes += frame.count
                    }
                }
                if !pending.isEmpty { try await ws.send(.data(pending)) }
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
        engine?.inputNode.removeTap(onBus: 0); engine?.stop(); engine = nil
        sink?.finish(); sink = nil
        // Bound draining time; a stalled send must not hold the UI indefinitely.
        let deadline = Task { try? await Task.sleep(for: .seconds(8)); if !Task.isCancelled { ws.cancel(with: .goingAway, reason: nil) } }
        defer { deadline.cancel() }
        await sender?.value
        do {
            try await ws.send(.string("{\"type\":\"endStream\"}"))
            await receiver?.value
        } catch { stop(); throw failure("Could not finalize the cloud transcript. Some final words may be missing.") }
        stop()
    }
    func stop() {
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
