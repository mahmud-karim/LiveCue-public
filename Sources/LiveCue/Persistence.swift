import Foundation
import SwiftData
import LiveCueCore

@Model
final class StoredSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var title: String
    @Attribute(.externalStorage) var payload: Data

    init(session: Session) throws {
        id = session.id
        startedAt = session.startedAt
        title = session.title
        payload = try JSONEncoder.liveCue.encode(session)
    }

    func decode() throws -> Session { try JSONDecoder.liveCue.decode(Session.self, from: payload) }
}

@MainActor
final class SessionRepository {
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: StoredSession.self, configurations: configuration)
        if !inMemory, let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: base.path)
        }
    }

    func all() -> [Session] {
        let descriptor = FetchDescriptor<StoredSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return (try? context.fetch(descriptor).compactMap { try? $0.decode() }) ?? []
    }

    func save(_ session: Session) throws {
        let sessionID = session.id
        let descriptor = FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == sessionID })
        if let stored = try context.fetch(descriptor).first {
            stored.title = session.title
            stored.startedAt = session.startedAt
            stored.payload = try JSONEncoder.liveCue.encode(session)
        } else {
            context.insert(try StoredSession(session: session))
        }
        try context.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<StoredSession>(predicate: #Predicate { $0.id == id })
        try context.fetch(descriptor).forEach(context.delete)
        try context.save()
    }
}

extension JSONEncoder {
    static var liveCue: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
}

extension JSONDecoder {
    static var liveCue: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}

