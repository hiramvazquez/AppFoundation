import Foundation
import SwiftData

@Model
final class LoginRecord {
    deinit {}
    @Attribute(.unique) var id: UUID
    var title: String

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

public protocol LoginStoring: Sendable {
    func fetchAll() async throws -> [LoginItem]
    func save(_ item: LoginItem) async throws
}

@ModelActor
public actor LoginStore: LoginStoring {
    public func fetchAll() async throws -> [LoginItem] {
        let descriptor = FetchDescriptor<LoginRecord>()
        let records = try modelContext.fetch(descriptor)
        return records.map { LoginItem(id: $0.id, title: $0.title) }
    }

    public func save(_ item: LoginItem) async throws {
        modelContext.insert(LoginRecord(id: item.id, title: item.title))
        try modelContext.save()
    }
}
