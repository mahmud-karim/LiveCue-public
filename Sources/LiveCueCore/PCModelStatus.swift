import Foundation

public struct PCModelStatus: Codable, Equatable {
    public var state: String
    public var model: String?
    public var busy: Bool
    public var elapsedSeconds: Int
    public var message: String
    public var isChanging: Bool { state == "starting" || state == "stopping" }
    public func isReady(for provider: String) -> Bool { state == "ready" && model == provider }
    public init(state: String, model: String? = nil, busy: Bool = false, elapsedSeconds: Int = 0, message: String) {
        self.state = state; self.model = model; self.busy = busy; self.elapsedSeconds = elapsedSeconds; self.message = message
    }
}
