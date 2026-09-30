import Foundation
import LiveCueCore

/// The PC address and credential are saved together. The protected app-container
/// copy supports LiveContainer installations whose Keychain access may change.
final class PairingStore {
    private let account: String
    private let file: URL
    init(testing: Bool = false) {
        account = testing ? "relayPairing-tests" : "relayPairing"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        file = directory.appendingPathComponent(testing ? "pairedPC-tests.json" : "pairedPC.json")
    }
    func load(legacyEndpoint: String = "") -> PairingPayload? {
        if let data = try? Data(contentsOf: file), let saved = try? PairingPayload.parse(String(decoding: data, as: UTF8.self)) {
            try? KeychainStore.set(String(decoding: data, as: UTF8.self), account: account)
            return saved
        }
        if let text = KeychainStore.get(account: account), let saved = try? PairingPayload.parse(text) { return saved }
        if account == "relayPairing", !legacyEndpoint.isEmpty, let token = KeychainStore.get(account: "relayToken"),
           let data = try? JSONSerialization.data(withJSONObject: ["endpoint": legacyEndpoint, "token": token]),
           let saved = try? PairingPayload.parse(String(decoding: data, as: UTF8.self)) {
            try? save(saved)
            return saved
        }
        return nil
    }
    func save(_ pairing: PairingPayload) throws {
        let data = try JSONEncoder().encode(pairing)
        _ = try PairingPayload.parse(String(decoding: data, as: UTF8.self))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var protected = file
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try protected.setResourceValues(values)
        // File protection is the persistent fallback if this LiveContainer
        // installation cannot write to its Keychain access group.
        try? KeychainStore.set(String(decoding: data, as: UTF8.self), account: account)
    }
    func removeTestKeychainCopy() {
        guard account == "relayPairing-tests" else { return }
        KeychainStore.remove(account: account)
    }
}
