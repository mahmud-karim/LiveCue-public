import Foundation

struct OpenRouterStreamResult {
    var id: String?
    var model: String?
    var text: String
    var usage: AssistantUsage?
}

/// SSE framing and answer extraction, separate from networking for regression tests.
/// Reasoning, provider errors and tool calls are never rendered as answer text.
struct OpenRouterStreamParser {
    private(set) var text = ""
    private(set) var done = false
    private var dataLines: [String] = []
    private var eventBytes = 0
    private var id: String?
    private var model: String?
    private var finishReason: String?
    private var usage: AssistantUsage?

    mutating func consumeLine(_ line: String) throws -> Bool {
        if done { return false }
        if line.isEmpty {
            guard !dataLines.isEmpty else { return false }
            let data = dataLines.joined(separator: "\n")
            dataLines = []; eventBytes = 0
            if data == "[DONE]" { done = true; return false }
            return try consumeEvent(Data(data.utf8), streaming: true)
        }
        guard line.hasPrefix("data:") else { return false } // comments, event/id/retry fields
        var value = String(line.dropFirst(5))
        if value.hasPrefix(" ") { value.removeFirst() }
        eventBytes += value.utf8.count
        guard eventBytes <= 128 * 1024 else { throw OpenRouterError.invalidResponse }
        dataLines.append(value)
        return false
    }

    private mutating func consumeEvent(_ data: Data, streaming: Bool) throws -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OpenRouterError.invalidResponse }
        if object["error"] != nil { throw OpenRouterError.unavailable }
        if let value = object["id"] as? String { id = value }
        if let value = object["model"] as? String { model = value }
        if let accounting = object["usage"] as? [String: Any] {
            let cost = (accounting["cost"] as? NSNumber)?.doubleValue ?? (accounting["cost"] as? String).flatMap(Double.init)
            usage = AssistantUsage(generationId: id, promptTokens: (accounting["prompt_tokens"] as? NSNumber)?.intValue,
                                   completionTokens: (accounting["completion_tokens"] as? NSNumber)?.intValue,
                                   costCredits: cost.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
        }
        let choices = object["choices"] as? [[String: Any]] ?? []
        guard let choice = choices.first(where: { ($0["index"] as? Int ?? 0) == 0 }) else { return false }
        if let reason = choice["finish_reason"] as? String {
            if reason == "length" { throw OpenRouterError.truncated }
            guard reason == "stop" else { throw OpenRouterError.invalidResponse }
            // Accounting frames may repeat the terminal finish reason.
            finishReason = reason
        }
        let message = choice[streaming ? "delta" : "message"] as? [String: Any] ?? [:]
        let content: String
        if let value = message["content"] as? String { content = value }
        else if let blocks = message["content"] as? [[String: Any]] {
            content = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined()
        } else { content = "" }
        guard text.utf8.count + content.utf8.count <= 1024 * 1024 else { throw OpenRouterError.invalidResponse }
        text += content
        return !content.isEmpty
    }

    func result() throws -> OpenRouterStreamResult {
        guard done, finishReason == "stop", !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw OpenRouterError.invalidResponse }
        var accounting = usage
        accounting?.generationId = id
        return OpenRouterStreamResult(id: id, model: model, text: text, usage: accounting)
    }

    static func completeJSON(_ data: Data) throws -> OpenRouterStreamResult {
        var parser = Self()
        _ = try parser.consumeEvent(data, streaming: false)
        parser.done = true
        return try parser.result()
    }
}
